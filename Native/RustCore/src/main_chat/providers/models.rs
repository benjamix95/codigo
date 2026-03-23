use app_core_protocol::main_chat_provider::{
    MainChatProviderBackend, MainChatProviderEvent, MainChatProviderEventKind,
    MainChatProviderSessionSnapshot,
};
use std::collections::{BTreeMap, VecDeque};
use std::process::Child;
use std::sync::atomic::AtomicBool;
use std::sync::{Arc, Mutex};

#[derive(Clone)]
pub struct ProviderSessionHandle {
    pub snapshot: Arc<Mutex<MainChatProviderSessionSnapshot>>,
    pub events: Arc<Mutex<VecDeque<MainChatProviderEvent>>>,
    pub child: Arc<Mutex<Option<Child>>>,
    pub cancelled: Arc<AtomicBool>,
}

impl ProviderSessionHandle {
    pub fn new(session_id: String, provider_id: String, backend: MainChatProviderBackend) -> Self {
        Self {
            snapshot: Arc::new(Mutex::new(MainChatProviderSessionSnapshot {
                session_id,
                provider_id,
                backend: Some(backend),
                status: "starting".to_string(),
                terminal_error: None,
                active_account_id: None,
                round_robin_index: 0,
                emitted_event_count: 0,
                last_failover_reason: None,
            })),
            events: Arc::new(Mutex::new(VecDeque::new())),
            child: Arc::new(Mutex::new(None)),
            cancelled: Arc::new(AtomicBool::new(false)),
        }
    }
}

pub fn make_started_event() -> MainChatProviderEvent {
    MainChatProviderEvent {
        kind: MainChatProviderEventKind::Started,
        text: String::new(),
        raw_type: None,
        payload: BTreeMap::new(),
    }
}

pub fn make_completed_event() -> MainChatProviderEvent {
    MainChatProviderEvent {
        kind: MainChatProviderEventKind::Completed,
        text: String::new(),
        raw_type: None,
        payload: BTreeMap::new(),
    }
}

pub fn make_text_delta_event(text: String) -> MainChatProviderEvent {
    MainChatProviderEvent {
        kind: MainChatProviderEventKind::TextDelta,
        text,
        raw_type: None,
        payload: BTreeMap::new(),
    }
}

pub fn make_text_replace_event(text: String) -> MainChatProviderEvent {
    MainChatProviderEvent {
        kind: MainChatProviderEventKind::TextReplace,
        text,
        raw_type: None,
        payload: BTreeMap::new(),
    }
}

pub fn make_raw_event(raw_type: &str, payload: BTreeMap<String, String>) -> MainChatProviderEvent {
    MainChatProviderEvent {
        kind: MainChatProviderEventKind::Raw,
        text: String::new(),
        raw_type: Some(raw_type.to_string()),
        payload,
    }
}

pub fn make_error_event(message: String) -> MainChatProviderEvent {
    MainChatProviderEvent {
        kind: MainChatProviderEventKind::Error,
        text: message,
        raw_type: None,
        payload: BTreeMap::new(),
    }
}
