pub const QUEUED: &str = "queued";
pub const DISCOVERY: &str = "discovery";
pub const AUDIT: &str = "audit";
pub const VERIFICATION: &str = "verification";
pub const PATCH_PREPARATION: &str = "patch_preparation";
pub const PUBLISH_READY: &str = "publish_ready";
pub const COMPLETED: &str = "completed";

pub const PHASE_ORDER: [&str; 6] = [
    DISCOVERY,
    AUDIT,
    VERIFICATION,
    PATCH_PREPARATION,
    PUBLISH_READY,
    COMPLETED,
];

pub fn phase_title(phase_id: &str) -> &'static str {
    match phase_id {
        DISCOVERY => "Avvio",
        AUDIT => "Controlli",
        VERIFICATION => "Verifica",
        PATCH_PREPARATION => "Preparazione fix",
        PUBLISH_READY => "Risultati pronti",
        COMPLETED => "Completata",
        _ => "Avvio",
    }
}

pub fn ledger_status(
    phase_id: &str,
    current_phase: &str,
    terminal: bool,
) -> &'static str {
    let current_rank = phase_rank(current_phase);
    let target_rank = phase_rank(phase_id);
    if terminal && current_phase == COMPLETED {
        return "completed";
    }
    if target_rank < current_rank {
        "completed"
    } else if target_rank == current_rank {
        if terminal && current_phase != COMPLETED {
            "blocked"
        } else {
            "running"
        }
    } else {
        "pending"
    }
}

pub fn steps_completed(current_phase: &str) -> i64 {
    match current_phase {
        COMPLETED => 6,
        PUBLISH_READY => 5,
        PATCH_PREPARATION => 4,
        VERIFICATION => 3,
        AUDIT => 2,
        DISCOVERY => 1,
        _ => 0,
    }
}

pub fn phase_rank(phase_id: &str) -> i64 {
    match phase_id {
        QUEUED => 0,
        DISCOVERY => 1,
        AUDIT => 2,
        VERIFICATION => 3,
        PATCH_PREPARATION => 4,
        PUBLISH_READY => 5,
        COMPLETED => 6,
        _ => 0,
    }
}
