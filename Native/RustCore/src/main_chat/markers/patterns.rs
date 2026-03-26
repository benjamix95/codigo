use regex::{Regex, RegexBuilder};
use std::sync::OnceLock;

fn regex(pattern: &str, case_insensitive: bool, multi_line: bool) -> Regex {
    RegexBuilder::new(pattern)
        .case_insensitive(case_insensitive)
        .multi_line(multi_line)
        .build()
        .expect("invalid hardcoded regex")
}

pub fn coderide_marker() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| regex(r"\[\s*CODERIDE\s*:[^\]\n]*\]", true, false))
}

/// Frammenti `[Policy error] …` iniettati dalla pipeline policy (mai mostrati in bolla/thinking).
pub fn policy_error_run() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| regex(r"(?i)\[Policy error\][^\n\r]*", false, false))
}

pub fn inline_marker_prefix() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| regex(r"\bmarkers\s*:\s*[a-z_][a-z0-9_]*\|", true, false))
}

pub fn inline_op_prefix() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| {
        regex(
            r"^\s*(?:Setting|Preparing|Starting|Initializing|Bootstrapping|Planning|Analyzing|Inspecting)\s+(?:initial\s+)?(?:task\s+panel(?:\s+and\s+todo\s+update)?|todo(?:\s+update)?|workflow(?:\s+steps?)?|project\s+analysis|analysis|plan|execution(?:\s+flow)?)(?:\s+and\s+todo\s+update)?\s+",
            true,
            true,
        )
    })
}

pub fn inline_marker_types() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| {
        regex(
            r"\b(?:todo_write|todo_read|plan_step(?:_update|_upsert|_batch_update|_reorder|_dependency_set)?|plan_create|plan_read|plan_set_walkthrough|plan_history_read|plan_diff|plan_request_user_input|read_batch(?:_started|_completed)?|web_search(?:_started|_completed|_failed)?|web_fetch(?:_started|_completed|_failed)?|instant_grep)\|",
            true,
            false,
        )
    })
}

pub fn inline_marker_broken() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| {
        regex(
            r"\b(?:markers)?[a-z_]*(?:todo_write|todo_read|do_write|do_read|plan_step(?:_update|_upsert|_batch_update|_reorder|_dependency_set)?|plan_create|plan_read|plan_set_walkthrough|plan_history_read|plan_diff|plan_request_user_input|read_batch(?:_started|_completed)?|web_search(?:_started|_completed|_failed)?|web_fetch(?:_started|_completed|_failed)?|instant_grep)\|",
            true,
            false,
        )
    })
}

pub fn technical_events() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| {
        regex(
            r"\b(?:coderide_show_task_panel|coderide_show_swarm_panel|read_batch_started|read_batch_completed|web_search_started|web_search_completed|web_search_failed|web_fetch_started|web_fetch_completed|web_fetch_failed|plan_step(?:_update|_upsert|_batch_update|_reorder|_dependency_set)?|plan_create|plan_read|plan_set_walkthrough|plan_history_read|plan_diff|plan_request_user_input|todo_write|todo_read|instant_grep)\b",
            true,
            false,
        )
    })
}

pub fn sticky_key_value() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| {
        regex(
            r"([A-Za-zÀ-ÖØ-öø-ÿ])((?:files|count|group_id|queryid|query|step_id|pathscope|matchescount|previewlines|status|priority|notes|title|id|task)=)",
            true,
            false,
        )
    })
}

pub fn single_key_value() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| {
        regex(
            r"\b(?:id|title|status|priority|notes|files|step_id|queryid|query|group_id|count|task)=[^\|\n\r]+(?:\||$)",
            true,
            false,
        )
    })
}

pub fn key_value_bracket() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| {
        regex(
            r"\b(?:id|title|status|priority|notes|files|step_id|queryid|query|group_id|count|task|pathscope|matchescount|previewlines)=[^\]\n\r]+\]",
            true,
            false,
        )
    })
}

pub fn trailing_space_newline() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| regex(r"\s+\n", false, false))
}

pub fn excessive_spaces() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| regex(r"[ \t]{2,}", false, false))
}

pub fn missing_space_after_punct() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| regex(r"([.!?])([A-Za-zÀ-ÖØ-öø-ÿ])", false, false))
}

pub fn excessive_newlines() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| regex(r"\n{3,}", false, false))
}

pub fn structured_payload() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| {
        regex(
            r"(?:\b[a-z_][a-z0-9_]*=[^\|\n\r]+(?:\|\s*|\s*$)){2,}",
            true,
            false,
        )
    })
}
