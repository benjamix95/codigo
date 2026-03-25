use std::fs::{self, File, OpenOptions};
use std::io;
use std::path::Path;

/// Modalità di lock per advisory file lock.
#[derive(Clone, Copy)]
pub enum LockMode {
    /// Lock condiviso (più lettori).
    Shared,
    /// Lock esclusivo (un solo scrittore).
    Exclusive,
}

/// Esegue `body` tenendo un advisory file lock (flock) sul file `.lock`
/// adiacente al path dato. Il lock viene rilasciato automaticamente
/// quando il `File` handle esce dallo scope (drop).
///
/// Se il lock non può essere acquisito entro ~10 secondi, ritorna errore.
pub fn with_file_lock<T, F>(path: &Path, mode: LockMode, body: F) -> Result<T, String>
where
    F: FnOnce() -> Result<T, String>,
{
    let lock_path = path.with_extension("lock");
    if let Some(parent) = lock_path.parent() {
        fs::create_dir_all(parent).map_err(|e| format!("lock dir: {e}"))?;
    }

    let lock_file = OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(false)
        .open(&lock_path)
        .map_err(|e| format!("lock open: {e}"))?;

    acquire_flock(&lock_file, mode)?;

    let result = body();

    // Lock rilasciato automaticamente al drop di `lock_file`.
    drop(lock_file);

    result
}

#[cfg(unix)]
fn acquire_flock(file: &File, mode: LockMode) -> Result<(), String> {
    use std::os::unix::io::AsRawFd;
    use std::time::Instant;

    let fd = file.as_raw_fd();
    let op = match mode {
        LockMode::Shared => libc::LOCK_SH | libc::LOCK_NB,
        LockMode::Exclusive => libc::LOCK_EX | libc::LOCK_NB,
    };

    let deadline = Instant::now() + std::time::Duration::from_secs(10);

    loop {
        let ret = unsafe { libc::flock(fd, op) };
        if ret == 0 {
            return Ok(());
        }

        let err = io::Error::last_os_error();
        if err.kind() != io::ErrorKind::WouldBlock {
            return Err(format!("flock: {err}"));
        }

        if Instant::now() >= deadline {
            return Err("flock: timeout after 10s".to_string());
        }

        std::thread::sleep(std::time::Duration::from_millis(50));
    }
}

#[cfg(not(unix))]
fn acquire_flock(_file: &File, _mode: LockMode) -> Result<(), String> {
    // Su piattaforme non-Unix, procedi senza lock (fallback).
    Ok(())
}
