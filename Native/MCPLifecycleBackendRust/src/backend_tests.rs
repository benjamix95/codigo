#[cfg(test)]
mod tests {
    use crate::backend::Backend;
    use serde_json::json;

    #[test]
    fn list_servers_registers_new_entries() {
        let mut backend = Backend::new();
        let response = backend.handle(
            "1".to_string(),
            "list_servers",
            json!({"servers":[{"id":"a","name":"A","command":"/bin/echo"}]}),
        );
        assert!(response.ok);
        assert_eq!(response.payload["servers"][0]["id"], "a");
    }
}
