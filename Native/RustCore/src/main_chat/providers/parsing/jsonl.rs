pub(crate) fn parse_jsonl_line(line: &str) -> Vec<serde_json::Value> {
    let trimmed = line.trim();
    if trimmed.is_empty() {
        return Vec::new();
    }
    if let Ok(value) = serde_json::from_str::<serde_json::Value>(trimmed) {
        return vec![value];
    }
    extract_json_objects(trimmed)
        .into_iter()
        .filter_map(|item| serde_json::from_str::<serde_json::Value>(&item).ok())
        .collect()
}

fn extract_json_objects(line: &str) -> Vec<String> {
    let mut objects = Vec::new();
    let mut depth = 0_i32;
    let mut in_string = false;
    let mut escaped = false;
    let mut start_index = None;
    for (index, ch) in line.char_indices() {
        if in_string {
            if escaped {
                escaped = false;
            } else if ch == '\\' {
                escaped = true;
            } else if ch == '"' {
                in_string = false;
            }
            continue;
        }
        match ch {
            '"' => in_string = true,
            '{' => {
                if depth == 0 {
                    start_index = Some(index);
                }
                depth += 1;
            }
            '}' => {
                depth -= 1;
                if depth == 0 {
                    if let Some(start_index) = start_index.take() {
                        objects.push(line[start_index..=index].to_string());
                    }
                }
            }
            _ => {}
        }
    }
    objects
}

#[cfg(test)]
mod tests {
    use super::parse_jsonl_line;

    #[test]
    fn parse_jsonl_line_handles_concatenated_objects() {
        let payloads = parse_jsonl_line(r#"{"a":1}{"b":2}"#);
        assert_eq!(payloads.len(), 2);
        assert_eq!(payloads[0]["a"].as_i64(), Some(1));
        assert_eq!(payloads[1]["b"].as_i64(), Some(2));
    }
}
