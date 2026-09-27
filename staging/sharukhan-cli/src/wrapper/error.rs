//! Typed errors for wrapper derivation.
//!
//! Every variant names the input that was wrong and what was expected, and the
//! measured value where there is one: "expected 1, found 0" for a slot, the
//! offending lines for a leftover, the field for a profile.

use std::fmt;

#[derive(Debug, Clone, PartialEq)]
pub enum WrapperError {
    /// A kernel.org release string does not match the accepted grammar.
    KernelRelease { input: String, why: String },
    /// A profile field failed validation.
    Profile { field: String, why: String },
    /// The base wrapper's `@sharukhan-wrapper` declaration is missing or bad.
    Declaration { why: String },
    /// A slot is missing, duplicated, unpaired, nested or unknown.
    Slot {
        name: String,
        expected: usize,
        found: usize,
        why: String,
    },
    /// The base contradicts itself or the profile.
    Base { why: String },
    /// A rendered slot still carries a base identity string.
    RenderLeak { slot: String, token: String },
    /// A target identity string already occurs in the base, so renaming
    /// could not be told apart from text that was already there.
    Collision { token: String, lines: Vec<String> },
    /// Base identity strings survived derivation.
    Leftover {
        tokens: Vec<String>,
        lines: Vec<String>,
    },
    /// The emitted script failed a validation step.
    Validation { step: String, measured: String },
    /// `--check` found the committed output differs from a fresh derivation.
    Drift {
        path: String,
        line: usize,
        expected: String,
        found: String,
    },
    /// Branch or source verification failed.
    Verify {
        what: String,
        expected: String,
        found: String,
    },
    /// Filesystem or external-command failure, with context.
    Io { context: String, why: String },
}

impl fmt::Display for WrapperError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            WrapperError::KernelRelease { input, why } => {
                write!(f, "kernel release '{input}': {why}")
            }
            WrapperError::Profile { field, why } => write!(f, "profile field '{field}': {why}"),
            WrapperError::Declaration { why } => {
                write!(f, "base wrapper declaration (# @sharukhan-wrapper ...): {why}")
            }
            WrapperError::Slot {
                name,
                expected,
                found,
                why,
            } => write!(
                f,
                "slot '{name}': expected {expected}, found {found}: {why}"
            ),
            WrapperError::Base { why } => write!(f, "base wrapper: {why}"),
            WrapperError::RenderLeak { slot, token } => write!(
                f,
                "rendered slot '{slot}' contains the base identity string '{token}'"
            ),
            WrapperError::Collision { token, lines } => write!(
                f,
                "the target identity string '{token}' already occurs in the base, so a rename \
                 could not be told apart from existing text:\n  {}",
                lines.join("\n  ")
            ),
            WrapperError::Leftover { tokens, lines } => write!(
                f,
                "base identity strings survived derivation ({}):\n  {}",
                tokens.join(", "),
                lines.join("\n  ")
            ),
            WrapperError::Validation { step, measured } => {
                write!(f, "validation '{step}' failed: {measured}")
            }
            WrapperError::Drift {
                path,
                line,
                expected,
                found,
            } => write!(
                f,
                "{path} differs from a fresh derivation at line {line}:\n  derived:   {expected}\n  committed: {found}"
            ),
            WrapperError::Verify {
                what,
                expected,
                found,
            } => write!(
                f,
                "verification of {what} failed: expected {expected}, found {found}"
            ),
            WrapperError::Io { context, why } => write!(f, "{context}: {why}"),
        }
    }
}

impl std::error::Error for WrapperError {}

pub type Result<T> = std::result::Result<T, WrapperError>;

pub fn io(context: impl Into<String>, why: impl fmt::Display) -> WrapperError {
    WrapperError::Io {
        context: context.into(),
        why: why.to_string(),
    }
}

pub fn profile(field: impl Into<String>, why: impl Into<String>) -> WrapperError {
    WrapperError::Profile {
        field: field.into(),
        why: why.into(),
    }
}
