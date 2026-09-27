//! Kernel wrapper derivation: a slot-marked, version-neutral base wrapper plus
//! a reviewed per-kernel profile yield the build wrapper for any kernel.org
//! release. See specs/features/kernel-wrapper.md.

pub mod base;
pub mod branch;
pub mod cli;
pub mod derive;
pub mod error;
pub mod escape;
pub mod identity;
pub mod kernelorg;
pub mod profile;
pub mod render;
pub mod validate;
