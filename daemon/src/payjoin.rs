//! PayJoin (BIP78) — lógica de receptor.
//!
//! Incremento 1: a parte PURA e testável do receptor — contribuir uma entrada
//! própria e ajustar a saída do receptor com a taxa certa. Sem carteira, sem
//! rede: dá para provar a matemática com `cargo test`.
//!
//! Os próximos incrementos ligam isto na carteira do nó (escolher um UTXO
//! confirmado e assinar a entrada contribuída, via `select_confirmed_utxos` /
//! `sign_owned_inputs` do ldk-node vendorizado) e expõem o endpoint `/payjoin`.

use ldk_node::bitcoin::{Amount, OutPoint, ScriptBuf, Transaction, TxIn, Witness};

/// Peso aproximado de uma entrada P2WPKH, em vbytes. A carteira do nó é P2WPKH
/// (SegWit nativo), então toda entrada que o receptor contribui tem ~68 vB.
const PESO_ENTRADA_P2WPKH_VB: f64 = 68.0;

#[derive(Debug, PartialEq, Eq)]
pub enum PayjoinErro {
    /// O índice da saída do receptor não existe na transação do remetente.
    SaidaInvalida,
    /// O UTXO contribuído não cobre nem a própria taxa — não vale contribuir.
    ContribuicaoInsuficiente,
    /// A transação do remetente não tem entradas (inválida).
    SemEntradas,
}

/// BIP78: o receptor adiciona a própria entrada [contrib_outpoint]/[contrib_value]
/// e aumenta a saída dele ([indice_saida_receptor]) em
/// `valor_contribuído − taxa_extra`, onde `taxa_extra` cobre o peso da entrada
/// adicionada ao [fee_rate_sat_vb] já acordado na transação original.
///
/// Assim o receptor paga a taxa da PRÓPRIA entrada (não empurra custo para o
/// remetente) e recebe o valor do PSBT original mais o seu próprio UTXO de volta
/// na saída — o PayJoin quebra a heurística de "todas as entradas são do mesmo
/// dono" sem o remetente pagar a mais.
///
/// Devolve a transação NÃO assinada; a assinatura da entrada contribuída entra
/// depois (carteira), e o remetente reassina as dele.
pub fn montar_proposta_payjoin(
    original: &Transaction,
    contrib_outpoint: OutPoint,
    contrib_value: Amount,
    indice_saida_receptor: usize,
    fee_rate_sat_vb: f64,
) -> Result<Transaction, PayjoinErro> {
    if original.input.is_empty() {
        return Err(PayjoinErro::SemEntradas);
    }
    if indice_saida_receptor >= original.output.len() {
        return Err(PayjoinErro::SaidaInvalida);
    }

    let taxa_extra = (PESO_ENTRADA_P2WPKH_VB * fee_rate_sat_vb).ceil() as u64;
    let contrib_sats = contrib_value.to_sat();
    if contrib_sats <= taxa_extra {
        return Err(PayjoinErro::ContribuicaoInsuficiente);
    }

    let mut tx = original.clone();

    // A entrada do receptor copia o `sequence` das entradas do remetente: BIP78
    // pede uniformidade para não entregar, pela diferença de sequence, qual
    // entrada é de quem.
    let sequence = tx.input[0].sequence;
    tx.input.push(TxIn {
        previous_output: contrib_outpoint,
        script_sig: ScriptBuf::new(),
        sequence,
        witness: Witness::new(),
    });

    let saida = &mut tx.output[indice_saida_receptor];
    saida.value = Amount::from_sat(saida.value.to_sat() + contrib_sats - taxa_extra);

    Ok(tx)
}

#[cfg(test)]
mod testes {
    use super::*;
    use ldk_node::bitcoin::hashes::Hash;
    use ldk_node::bitcoin::{
        absolute::LockTime, transaction::Version, Sequence, TxOut, Txid,
    };

    fn entrada(seq: Sequence) -> TxIn {
        TxIn {
            previous_output: OutPoint::new(Txid::all_zeros(), 0),
            script_sig: ScriptBuf::new(),
            sequence: seq,
            witness: Witness::new(),
        }
    }

    fn tx_original(valor_saida_receptor: u64, seq: Sequence) -> Transaction {
        Transaction {
            version: Version::TWO,
            lock_time: LockTime::ZERO,
            input: vec![entrada(seq)],
            output: vec![TxOut {
                value: Amount::from_sat(valor_saida_receptor),
                script_pubkey: ScriptBuf::new(),
            }],
        }
    }

    fn contrib() -> OutPoint {
        OutPoint::new(Txid::all_zeros(), 1)
    }

    #[test]
    fn adiciona_entrada_e_bomba_saida_com_taxa_certa() {
        let seq = Sequence::ENABLE_RBF_NO_LOCKTIME;
        let original = tx_original(100_000, seq);
        let out =
            montar_proposta_payjoin(&original, contrib(), Amount::from_sat(50_000), 0, 2.0)
                .expect("deve montar");

        // Agora há duas entradas.
        assert_eq!(out.input.len(), 2);
        // taxa_extra = ceil(68 * 2.0) = 136 sats.
        // saída = 100_000 + 50_000 − 136 = 149_864.
        assert_eq!(out.output[0].value.to_sat(), 149_864);
        // O receptor copiou o sequence do remetente.
        assert_eq!(out.input[1].sequence, seq);
        // A entrada contribuída é a esperada.
        assert_eq!(out.input[1].previous_output, contrib());
    }

    #[test]
    fn taxa_extra_arredonda_para_cima() {
        let original = tx_original(100_000, Sequence::ENABLE_RBF_NO_LOCKTIME);
        // fee 1.5 sat/vB → ceil(68 * 1.5) = ceil(102.0) = 102.
        let out =
            montar_proposta_payjoin(&original, contrib(), Amount::from_sat(10_000), 0, 1.5)
                .unwrap();
        assert_eq!(out.output[0].value.to_sat(), 100_000 + 10_000 - 102);
    }

    #[test]
    fn recusa_contribuicao_menor_que_a_taxa() {
        let original = tx_original(100_000, Sequence::ENABLE_RBF_NO_LOCKTIME);
        // 100 sats de UTXO não cobrem a taxa_extra (136) a 2 sat/vB.
        let r = montar_proposta_payjoin(&original, contrib(), Amount::from_sat(100), 0, 2.0);
        assert_eq!(r, Err(PayjoinErro::ContribuicaoInsuficiente));
    }

    #[test]
    fn recusa_indice_de_saida_invalido() {
        let original = tx_original(100_000, Sequence::ENABLE_RBF_NO_LOCKTIME);
        let r = montar_proposta_payjoin(&original, contrib(), Amount::from_sat(50_000), 5, 2.0);
        assert_eq!(r, Err(PayjoinErro::SaidaInvalida));
    }

    #[test]
    fn recusa_transacao_sem_entradas() {
        let mut original = tx_original(100_000, Sequence::ENABLE_RBF_NO_LOCKTIME);
        original.input.clear();
        let r = montar_proposta_payjoin(&original, contrib(), Amount::from_sat(50_000), 0, 2.0);
        assert_eq!(r, Err(PayjoinErro::SemEntradas));
    }
}
