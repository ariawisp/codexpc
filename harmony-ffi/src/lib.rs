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
pub extern "C" fn harmony_render_system_user_tokens(
    system_instructions: *const c_char,
    user_parts: *const *const c_char,
    user_len: usize,
    out_tokens: *mut *mut u32,
    out_len: *mut usize,
) -> c_int {
    if out_tokens.is_null() || out_len.is_null() {
        return -1;
    }
    let mut sys_str = "";
    if !system_instructions.is_null() {
        let sys_c = unsafe { CStr::from_ptr(system_instructions) };
        match sys_c.to_str() {
            Ok(s) => sys_str = s,
            Err(_) => return -2,
        }
    }

    let mut users: Vec<String> = Vec::new();
    if user_len > 0 {
        if user_parts.is_null() {
            return -3;
        }
        for i in 0..user_len {
            // SAFETY: bounds checked by user_len
            let ptr = unsafe { *user_parts.add(i) };
            if ptr.is_null() { continue; }
            let cs = unsafe { CStr::from_ptr(ptr) };
            match cs.to_str() {
                Ok(s) => users.push(s.to_owned()),
                Err(_) => return -4,
            }
        }
    }

    let enc = match load_harmony_encoding(HarmonyEncodingName::HarmonyGptOss) {
        Ok(e) => e,
        Err(_) => return -5,
    };

    let mut msgs: Vec<Message> = Vec::new();
    if !sys_str.is_empty() {
        msgs.push(Message::from_role_and_content(Role::System, sys_str));
    }
    for u in users.into_iter() {
        msgs.push(Message::from_role_and_content(Role::User, u));
    }
    let convo = Conversation::from_messages(msgs);

    let toks = match enc.render_conversation_for_completion(&convo, Role::Assistant, None) {
        Ok(v) => v,
        Err(_) => return -6,
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
