let strip_prefix ~prefix s =
  if String.starts_with ~prefix s then
    let prefix_len = String.length prefix in
    Some (String.sub s prefix_len (String.length s - prefix_len))
  else None

let strip_suffix ~suffix s =
  if String.ends_with ~suffix s then
    let suffix_len = String.length suffix in
    Some (String.sub s (String.length s - suffix_len) suffix_len)
  else None

(* Copypasted from std *)
let is_space = function ' ' | '\012' | '\n' | '\r' | '\t' -> true | _ -> false

(* most readable ocaml code *)
type split_whitespace_state = { seq : string Seq.t; start : int Option.t }

(* this function will appear in my dreams tonight *)
let split_whitespace : string -> string Seq.t =
 fun s ->
  let indices = Seq.take (String.length s) (Seq.ints 0) in
  let finish (state : split_whitespace_state) i =
    match state.start with
    | None -> state.seq
    | Some start ->
        Seq.append state.seq (Seq.return (String.sub s start (i - start)))
  in
  let f (cur : split_whitespace_state) i =
    let c = String.get s i in
    match is_space c with
    | true -> { seq = finish cur i; start = None }
    | false -> (
        match cur.start with
        | Some _ -> cur
        | None -> { seq = cur.seq; start = Some i })
  in
  finish
    (Seq.fold_left f { seq = Seq.empty; start = None } indices)
    (String.length s)

let head (list : 'a list) : 'a option =
  match list with head :: _tail -> Some head | [] -> None
