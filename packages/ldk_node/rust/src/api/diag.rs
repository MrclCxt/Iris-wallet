use std::ffi::CString;
use std::sync::Once;

static HOOK: Once = Once::new();

// `c_char` NAO e `i8` em todo lugar: no Android ARM (aarch64 e armv7, que sao
// justamente os aparelhos reais) ele e `u8`. Fixar `i8` aqui compilava no
// desktop e nos emuladores x86, e quebrava a compilacao Rust so no alvo ARM —
// e o Gradle seguia empacotando a biblioteca antiga sem falhar o build.
// `CString::as_ptr()` ja devolve `*const c_char`, entao os tipos batem sozinhos.
#[cfg(target_os = "android")]
extern "C" {
    fn __android_log_write(
        prio: i32,
        tag: *const std::os::raw::c_char,
        text: *const std::os::raw::c_char,
    ) -> i32;
}

fn escrever(msg: &str) {
    #[cfg(target_os = "android")]
    {
        const ERROR: i32 = 6;
        if let (Ok(tag), Ok(txt)) = (CString::new("IrisRust"), CString::new(msg)) {
            unsafe {
                __android_log_write(ERROR, tag.as_ptr(), txt.as_ptr());
            }
        }
    }
    #[cfg(not(target_os = "android"))]
    {
        let _ = CString::new(msg);
        eprintln!("[IrisRust] {}", msg);
    }
}

/// Um `panic!` do Rust cruzando a FFI aborta o processo sem desenrolar a pilha,
/// e a mensagem morre com ele: nao aparece no logcat nem no tombstone, so
/// sobra um SIGABRT sem explicacao. Este gancho grava a mensagem ANTES do
/// abort, que e a unica janela para saber o que de fato quebrou.
pub fn instalar_gancho_de_panico() {
    HOOK.call_once(|| {
        let anterior = std::panic::take_hook();
        std::panic::set_hook(Box::new(move |info| {
            let local = info
                .location()
                .map(|l| format!("{}:{}:{}", l.file(), l.line(), l.column()))
                .unwrap_or_else(|| "local desconhecido".to_string());

            let msg = if let Some(s) = info.payload().downcast_ref::<&str>() {
                (*s).to_string()
            } else if let Some(s) = info.payload().downcast_ref::<String>() {
                s.clone()
            } else {
                "payload nao textual".to_string()
            };

            escrever(&format!("PANIC em {} :: {}", local, msg));

            let thread = std::thread::current();
            escrever(&format!(
                "PANIC na thread {:?}",
                thread.name().unwrap_or("sem nome")
            ));

            // Sem o rastro, "Layout invalido" so diz que ALGUM Vec foi remontado com capacidade
            // podre — nao QUAL. force_capture ignora a RUST_BACKTRACE, que nao da para definir
            // num app Android.
            let rastro = std::backtrace::Backtrace::force_capture();
            for linha in format!("{}", rastro).lines() {
                escrever(&format!("  {}", linha));
            }

            anterior(info);
        }));
        escrever("gancho de panico instalado");
        relatar_biblioteca_nativa();
    });
}

/// Imprime no log as constantes de varredura compiladas nesta biblioteca nativa.
///
/// O fonte nao serve como prova do que roda no aparelho: quando o build Rust do Android falha,
/// o Gradle empacota a `.so` anterior sem quebrar o build. Um celular preso em `stop_gap=20` nao
/// enxerga fundos em indices altos e mostra saldo menor que o PC com a MESMA semente — foi
/// exatamente o sintoma. Esta linha no logcat distingue "a correcao nao funcionou" de "a
/// correcao nao chegou".
fn relatar_biblioteca_nativa() {
    let (gap, concorrencia, timeout_varredura) = ldk_node::iris_parametros_de_varredura();
    escrever(&format!(
        "lib nativa em uso: stop_gap={} concorrencia={} timeout_varredura={}s",
        gap, concorrencia, timeout_varredura
    ));
}
