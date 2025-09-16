use std::ffi::CStr;
use std::os::raw::{c_char, c_int};

use openai_harmony::chat::{Conversation, Message, Role};
use openai_harmony::{load_harmony_encoding, HarmonyEncodingName};

#[no_mangle]
pub extern "C" fn harmony_render_system_tokens(
    instructions: *const c_char,
    out_tokens: *mut *mut u32,
    out_len: *mut usize,
) -> c_int {
    if instructions.is_null() || out_tokens.is_null() || out_len.is_null() {
        return -1;
    }
    let instr = unsafe { CStr::from_ptr(instructions) };
    let instr_str = match instr.to_str() {
        Ok(s) => s,
        Err(_) => return -2,
    };

    let enc = match load_harmony_encoding(HarmonyEncodingName::HarmonyGptOss) {
        Ok(e) => e,
        Err(_) => return -3,
    };

    let convo = Conversation::from_messages([Message::from_role_and_content(
        Role::System,
        instr_str,
    )]);

    let toks = match enc.render_conversation_for_completion(&convo, Role::Assistant, None) {
        Ok(v) => v,
        Err(_) => return -4,
    };

    let len = toks.len();
    let mut boxed = toks.into_boxed_slice();
    let ptr = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    unsafe {
        *out_tokens = ptr;
        *out_len = len;
    }
    0
}

#[no_mangle]
pub extern "C" fn harmony_tokens_free(ptr: *mut u32, len: usize) {
    if ptr.is_null() { return; }
    unsafe {
        let _ = Vec::from_raw_parts(ptr, len, len);
    }
}
