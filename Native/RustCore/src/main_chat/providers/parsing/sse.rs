pub(crate) fn sse_data_payload(line: &str) -> Option<&str> {
    let trimmed = line.trim();
    if let Some(payload) = trimmed.strip_prefix("data: ") {
        return Some(payload.trim());
    }
    None
}

#[cfg(test)]
mod tests {
    use super::sse_data_payload;

    #[test]
    fn extracts_sse_payload() {
        assert_eq!(sse_data_payload("data: hello"), Some("hello"));
        assert_eq!(sse_data_payload("event: ping"), None);
    }
}
