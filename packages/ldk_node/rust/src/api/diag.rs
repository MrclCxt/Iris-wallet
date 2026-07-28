use std::ffi::CString;
use std::sync::Once;

static HOOK: Once = Once::new();

#[cfg(target_os = "android")]
extern "C" {
    fn __android_log_write(prio: i32, tag: *const i8, text: *const i8) -> i32;
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

            anterior(info);
        }));
        escrever("gancho de panico instalado");
    });
}
