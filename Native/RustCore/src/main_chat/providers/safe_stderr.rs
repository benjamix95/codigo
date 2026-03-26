//! Logging su stderr senza panic: in host macOS (app GUI) stderr può restituire EIO;
//! `eprintln!` in quel caso fa panic con `failed printing to stderr`.

#[macro_export]
macro_rules! provider_stderr_eprintln {
    () => {{
        use std::io::Write as _;
        let mut w = std::io::stderr().lock();
        let _ = w.write_all(b"\n");
    }};
    ($($arg:tt)*) => {{
        use std::io::Write as _;
        let mut w = std::io::stderr().lock();
        let _ = writeln!(w, $($arg)*);
    }};
}
