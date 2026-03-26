//! Audit bug: pattern test/crash, state/API, git/diff.

mod bugs_git;
mod bugs_nil_tests;
mod bugs_state_risks;

pub(crate) use bugs_git::{
    run_bug_dependency_drift, run_bug_diff_semantics, run_bug_hotspots,
};
pub(crate) use bugs_nil_tests::{run_bug_nil_crash_paths, run_bug_test_gaps, run_bug_test_impact};
pub(crate) use bugs_state_risks::{
    run_bug_api_contracts, run_bug_diff_risks, run_bug_state_machine,
};
