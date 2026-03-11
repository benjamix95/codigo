use super::models::{
    build_index_response, normalize_json_array_payload, normalize_json_payload,
    BugHunterCommandRecord, BugHunterSnapshotValue, ReviewCommandRecord, ReviewPersistenceIndexRequest,
    ReviewPersistenceIndexResponse, ReviewPersistencePayloadRequest, ReviewPersistencePayloadResponse,
    ReviewSnapshotValue,
};

pub fn encode_review_snapshot_response(request: ReviewPersistencePayloadRequest) -> ReviewPersistencePayloadResponse {
    normalize_json_payload::<ReviewSnapshotValue>(&request.payload)
}

pub fn decode_review_snapshot_response(request: ReviewPersistencePayloadRequest) -> ReviewPersistencePayloadResponse {
    normalize_json_payload::<ReviewSnapshotValue>(&request.payload)
}

pub fn encode_bughunter_snapshot_response(request: ReviewPersistencePayloadRequest) -> ReviewPersistencePayloadResponse {
    normalize_json_payload::<BugHunterSnapshotValue>(&request.payload)
}

pub fn decode_bughunter_snapshot_response(request: ReviewPersistencePayloadRequest) -> ReviewPersistencePayloadResponse {
    normalize_json_payload::<BugHunterSnapshotValue>(&request.payload)
}

pub fn encode_review_commands_response(request: ReviewPersistencePayloadRequest) -> ReviewPersistencePayloadResponse {
    normalize_json_array_payload::<ReviewCommandRecord>(&request.payload)
}

pub fn decode_review_commands_response(request: ReviewPersistencePayloadRequest) -> ReviewPersistencePayloadResponse {
    normalize_json_array_payload::<ReviewCommandRecord>(&request.payload)
}

pub fn encode_bughunter_commands_response(request: ReviewPersistencePayloadRequest) -> ReviewPersistencePayloadResponse {
    normalize_json_array_payload::<BugHunterCommandRecord>(&request.payload)
}

pub fn decode_bughunter_commands_response(request: ReviewPersistencePayloadRequest) -> ReviewPersistencePayloadResponse {
    normalize_json_array_payload::<BugHunterCommandRecord>(&request.payload)
}

pub fn build_review_index_response(request: ReviewPersistenceIndexRequest) -> ReviewPersistenceIndexResponse {
    build_index_response(request)
}
