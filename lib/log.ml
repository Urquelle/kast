type level = Error | Warn | Info | Debug | Trace | Never

let max_level = ref Info
let with_level level s = if level <= !max_level then prerr_endline s
let error = with_level Error
let warn = with_level Warn
let info = with_level Info
let debug = with_level Debug
let trace = with_level Trace
let never = with_level Never
