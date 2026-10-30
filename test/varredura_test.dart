import 'package:flutter_test/flutter_test.dart';
import 'package:iris_wallet/core/varredura.dart';
import 'package:iris_wallet/nostr/chaves.dart';

/// Varredura de chave avulsa contra vetores conhecidos. A prova final — o
/// Bitcoin Core aceitar a transação — está em scripts/regtest_canal.py.
void main() {
  test('WIF não comprimida (vetor clássico)', () {
    final k = ChaveAvulsa.deWif('5HueCGU8rMjxEXxiPuD5BDku4MkFqeZyd4dZ1jvhTVqvbTLvyTJ');
    expect(paraHex(k.privada),
        '0c28fca386c7a227600b2fe50b7cae11ec86d3bf1fbe471be89827e19d72aa1d');
    expect(k.comprimida, isFalse);
    expect(k.principal, isTrue);
    expect(k.scripts, hasLength(1), reason: 'não comprimida: só legado');
  });

  test('WIF comprimida', () {
    final k = ChaveAvulsa.deWif('KwdMAjGmerYanjeui5SHS7JkmpZvVipYvB2LJGU1ZxJwYvP98617');
    expect(paraHex(k.privada),
        '0c28fca386c7a227600b2fe50b7cae11ec86d3bf1fbe471be89827e19d72aa1d');
    expect(k.comprimida, isTrue);
    expect(k.scripts, hasLength(2));
  });

  test('WIF com um caractere trocado é recusada', () {
    expect(() => ChaveAvulsa.deWif('5HueCGU8rMjxEXxiPuD5BDku4MkFqeZyd4dZ1jvhTVqvbTLvyTK'),
        throwsFormatException);
  });

  test('sighash BIP143 do exemplo oficial (P2WPKH nativo)', () {
    final h = sighashBip143ParaTeste(
      versao: 1,
      prevouts: deHex(
          'fff7f7881a8099afa6940d42d1e7f6362bec38171ea3edf433541db4e4ad969f00000000'
          'ef51e1b804cc89d182d279655c3aa89e815b1b309fe287d9b2b55d57b90ec68a01000000'),
      sequencias: deHex('eeffffffffffffff'),
      entrada: deHex(
          'ef51e1b804cc89d182d279655c3aa89e815b1b309fe287d9b2b55d57b90ec68a01000000'),
      codigo: deHex('1976a9141d0f172a0ecb48aee1be1f2687d2963ae33f71a188ac'),
      valor: 600000000,
      sequencia: 0xffffffff,
      saidas: deHex(
          '202cb206000000001976a9148280b37df378db99f66f85c95a783a76ac7a6d5988ac'
          '9093510d000000001976a9143bde42dbee7e4dbe6a21b2d50ce2f0167faa815988ac'),
      locktime: 0x11,
    );
    expect(paraHex(h),
        'c37af31116d1b27caf68aae9e3ac82f1477929014d5b917657d0eb49478cb670');
  });

  test('endereço SegWit vira o scriptPubKey certo', () {
    expect(paraHex(scriptDeEndereco('bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4', 'bc')),
        '0014751e76e8199196d454941c45d1b3a323f1433bd6');
    expect(() => scriptDeEndereco('bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4', 'tb'),
        throwsFormatException);
  });

  test('assinatura DER com S baixo', () {
    final der = assinarDer(BigInt.from(1), deHex('00' * 32));
    expect(der[0], 0x30);
    expect(der.length, der[1] + 2);
  });

  test('sem saldo suficiente para a taxa, recusa', () {
    final k = ChaveAvulsa.deWif('KwdMAjGmerYanjeui5SHS7JkmpZvVipYvB2LJGU1ZxJwYvP98617');
    expect(
        () => varrer(
            chave: k,
            utxos: [Utxo('00' * 32, 0, 600, k.scripts.first)],
            destino: k.scripts.first,
            satsPorVbyte: 10),
        throwsFormatException);
  });

  test('chave nova: WIF e endereço SegWit voltam iguais', () {
    final k = ChaveAvulsa.nova(principal: false);
    final volta = ChaveAvulsa.deWif(k.wif);
    expect(paraHex(volta.privada), paraHex(k.privada));
    expect(volta.principal, isFalse);
    expect(ChaveAvulsa.pareceWif(k.wif), isTrue);
    final addr = k.enderecoSegwit('tb');
    expect(paraHex(scriptDeEndereco(addr, 'tb')), paraHex(k.scripts.first));
  });

  test('endereço SegWit da chave 1 (vetor conhecido)', () {
    final k = ChaveAvulsa.deWif('KwDiBf89QgGbjEhKnhXJuH7LrciVrZi3qYjgd9M7rFU73sVHnoWn');
    expect(k.enderecoSegwit('bc'), 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4');
  });
}
