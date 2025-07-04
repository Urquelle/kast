open Std
open Kast_util
module Compiler = Kast_compiler
module Token = Kast_token
module Lexer = Kast_lexer
module Ast = Kast_ast
module Parser = Kast_parser
open Kast_types

module Args = struct
  type args = { dummy : unit }
  type t = args

  let parse : string list -> args = function
    | [] -> { dummy = () }
    | arg :: _rest -> fail "Unexpected arg %S" arg
end

module Lsp = Linol.Lsp

type state_after_processing = {
  parsed : Parser.result option;
  compiled : expr option;
}

let process_some_input_file (source : source) : state_after_processing =
  let parsed =
    try
      let result = Parser.parse source Kast_default_syntax.ruleset in
      Some result
    with _ -> None
  in
  let ast = Option.bind parsed (fun ({ ast; _ } : Parser.result) -> ast) in
  let compiled =
    Option.bind ast (fun ast ->
        let compiler = Compiler.init () in
        try Some (Compiler.compile compiler Expr ast) with _ -> None)
  in
  { parsed; compiled }

module Tokens = struct
  type token_shape =
    | Keyword of Token.Shape.t
    | Value of Token.Shape.t
    | Comment of Token.Shape.comment
    | Unknown of Token.Shape.t

  type token = {
    token : token_shape;
    span : span;
  }

  let rec collect : Ast.t -> token Seq.t =
   fun { shape; span = _ } ->
    match shape with
    | Ast.Simple { comments_before; token } ->
        Seq.append
          (comments_before |> List.to_seq
          |> Seq.map (fun (comment : Token.comment) ->
                 { token = Comment comment.shape; span = comment.span }))
          (List.to_seq [ { token = Value token.shape; span = token.span } ])
    | Ast.Complex { parts; _ } ->
        parts |> List.to_seq
        |> Seq.flat_map (function
             | Ast.Value ast -> collect ast
             | Ast.Keyword token ->
                 List.to_seq
                   [ { token = Keyword token.shape; span = token.span } ]
             | Ast.Comment comment ->
                 List.to_seq
                   [ { token = Comment comment.shape; span = comment.span } ])
    | Ast.Syntax { value_after; tokens; _ } ->
        Seq.append
          (tokens |> List.to_seq
          |> Seq.map (fun (token : Token.t) ->
                 { token = Unknown token.shape; span = token.span }))
          (value_after |> Option.to_seq |> Seq.flat_map collect)
end

let diagnostics (_state : state_after_processing) : Lsp.Types.Diagnostic.t list
    =
  []

let semanticTokensProvider =
  let legend =
    Lsp.Types.SemanticTokensLegend.create
      ~tokenTypes:
        [
          "namespace";
          "class";
          "enum";
          "interface";
          "struct";
          "typeParameter";
          "type";
          "parameter";
          "variable";
          "property";
          "enumMember";
          "decorator";
          "event";
          "function";
          "method";
          "macro";
          "label";
          "comment";
          "string";
          "keyword";
          "number";
          "regexp";
          "operator";
        ]
      ~tokenModifiers:
        [
          "declaration";
          "definition";
          "readonly";
          "static";
          "deprecated";
          "abstract";
          "async";
          "modification";
          "documentation";
          "defaultLibrary";
        ]
  in
  Lsp.Types.SemanticTokensRegistrationOptions.create ~full:(`Bool true) ~legend
    ()

module IO = Linol_lwt.IO_lwt

type linecol = {
  line : int;
  column : int;
}

let linecol (pos : position) : linecol =
  { line = pos.line; column = pos.column }

let span_to_range (span : span) : Lsp.Types.Range.t =
  {
    start = { line = span.start.line - 1; character = span.start.column - 1 };
    end_ = { line = span.finish.line - 1; character = span.finish.column - 1 };
  }

let rec find_spans_start_biggest (ast : Ast.t) (pos : position) : span list =
  if Span.contains pos ast.span then
    ast.span
    ::
    (match ast.shape with
    | Simple _ -> []
    | Complex { children; _ } -> (
        let child_spans =
          children |> Tuple.to_seq
          |> Seq.find_map (fun (_member, child) ->
                 let child_spans = find_spans_start_biggest child pos in
                 if List.length child_spans = 0 then None else Some child_spans)
        in
        match child_spans with
        | None -> []
        | Some child_spans -> child_spans)
    | Syntax { value_after; _ } -> (
        match value_after with
        | None -> []
        | Some value -> find_spans_start_biggest value pos))
  else []

let rec inlay_hints :
    'a. 'a Compiler.compiled_kind -> 'a -> Lsp.Types.InlayHint.t Seq.t =
 fun (type a) (kind : a Compiler.compiled_kind) (compiled : a) ->
  let span, ((type_hint : string option), rest) =
    match kind with
    | Expr ->
        ( compiled.span,
          match compiled.shape with
          | E_Constant _ -> (None, Seq.empty)
          | E_Binding _ -> (None, Seq.empty)
          | E_Then { a; b } ->
              (None, Seq.append (inlay_hints Expr a) (inlay_hints Expr b))
          | E_Stmt { expr } -> (None, inlay_hints Expr expr)
          | E_Scope { expr } -> (None, inlay_hints Expr expr)
          | E_Fn { arg; body } ->
              ( None,
                Seq.append (inlay_hints Pattern arg) (inlay_hints Expr body) )
          | E_Tuple { tuple } ->
              ( None,
                tuple |> Tuple.to_seq
                |> Seq.flat_map (fun (_member, expr) -> inlay_hints Expr expr)
              )
          | E_Apply { f; arg } ->
              (None, Seq.append (inlay_hints Expr f) (inlay_hints Expr arg))
          | E_Assign { assignee; value } ->
              ( None,
                Seq.append
                  (inlay_hints Assignee assignee)
                  (inlay_hints Expr value) ) )
    | Pattern ->
        ( compiled.span,
          match compiled.shape with
          | P_Placeholder -> (None, Seq.empty)
          | P_Unit -> (None, Seq.empty)
          | P_Binding _ ->
              (Some (make_string ":: %a" Ty.print compiled.ty), Seq.empty) )
    | Assignee ->
        ( compiled.span,
          match compiled.shape with
          | A_Placeholder -> (None, Seq.empty)
          | A_Unit -> (None, Seq.empty)
          | A_Binding _ -> (None, Seq.empty)
          | A_Let pattern -> (None, inlay_hints Pattern pattern) )
  in
  let hint : Lsp.Types.InlayHint.t option =
    type_hint
    |> Option.map (fun type_hint : Lsp.Types.InlayHint.t ->
           {
             position =
               {
                 line = span.finish.line - 1;
                 character = span.finish.column - 1;
               };
             label = `String type_hint;
             kind = Some Type;
             textEdits = None;
             tooltip = None;
             paddingLeft = Some true;
             paddingRight = Some false;
             data = None;
           })
  in
  Seq.append (hint |> Option.to_seq) rest

let inlay_hints (expr : expr) : Lsp.Types.InlayHint.t list =
  inlay_hints Expr expr |> List.of_seq

class lsp_server =
  object (self)
    inherit Linol_lwt.Jsonrpc2.server

    method! config_modify_capabilities (c : Lsp.Types.ServerCapabilities.t) :
        Lsp.Types.ServerCapabilities.t =
      {
        c with
        documentFormattingProvider =
          Some (`DocumentFormattingOptions { workDoneProgress = Some false });
        semanticTokensProvider =
          Some (`SemanticTokensRegistrationOptions semanticTokensProvider);
        selectionRangeProvider = Some (`Bool true);
        inlayHintProvider = Some (`Bool true);
      }

    (* one env per document *)
    val buffers : (Lsp.Types.DocumentUri.t, state_after_processing) Hashtbl.t =
      Hashtbl.create 32

    method spawn_query_handler f = Linol_lwt.spawn f

    (* We define here a helper method that will:
       - process a document
       - store the state resulting from the processing
       - return the diagnostics from the new state
    *)
    method private _on_doc ~(notify_back : Linol_lwt.Jsonrpc2.notify_back)
        (uri : Lsp.Types.DocumentUri.t) (contents : string) =
      Log.info "processing file %S" (Lsp.Uri.to_path uri);

      let new_state =
        process_some_input_file
          { filename = File (Lsp.Types.DocumentUri.to_path uri); contents }
      in
      Hashtbl.replace buffers uri new_state;
      let diags = diagnostics new_state in
      notify_back#send_diagnostic diags

    (* We now override the [on_notify_doc_did_open] method that will be called
       by the server each time a new document is opened. *)
    method on_notif_doc_did_open ~notify_back d ~content : unit Linol_lwt.t =
      self#_on_doc ~notify_back d.uri content

    (* Similarly, we also override the [on_notify_doc_did_change] method that will be called
       by the server each time a new document is opened. *)
    method on_notif_doc_did_change ~notify_back d _c ~old_content:_old
        ~new_content =
      self#_on_doc ~notify_back d.uri new_content

    (* On document closes, we remove the state associated to the file from the global
       hashtable state, to avoid leaking memory. *)
    method on_notif_doc_did_close ~notify_back:_ d : unit Linol_lwt.t =
      Hashtbl.remove buffers d.uri;
      Linol_lwt.return ()

    method! on_req_inlay_hint ~notify_back:_ ~id:_ ~uri
        ~(range : Lsp.Types.Range.t) () : Lsp.Types.InlayHint.t list option IO.t
        =
      let _ = range in
      Log.info "got inlay hint req";
      let { compiled; _ } = Hashtbl.find buffers uri in
      match compiled with
      | None -> IO.return None
      | Some expr ->
          let hints = inlay_hints expr in
          Log.info "replying to inlay hint req";
          IO.return <| Some hints

    method private on_selection_range :
        notify_back:Linol_lwt.Jsonrpc2.notify_back ->
        Lsp.Types.SelectionRangeParams.t ->
        Lsp.Types.SelectionRange.t list Lwt.t =
      fun ~notify_back:_ params ->
        Log.info "got selection range request";
        let { parsed; _ } = Hashtbl.find buffers params.textDocument.uri in
        match parsed with
        | Some { ast = Some ast; eof; _ } ->
            params.positions
            |> List.map (fun (position : Lsp.Types.Position.t) ->
                   let pos : position =
                     {
                       (* we dont need it *)
                       index = 0;
                       line = position.line + 1;
                       column = position.character + 1;
                     }
                   in
                   let full_file : span =
                     {
                       start = Position.beginning;
                       finish = eof;
                       filename =
                         File (params.textDocument.uri |> Lsp.Uri.to_path);
                     }
                   in
                   let spans = full_file :: find_spans_start_biggest ast pos in
                   Log.info "SPANS: %a" (List.print Span.print) spans;
                   spans
                   |> List.fold_left
                        (fun parent (span : span) ->
                          Some
                            ({ parent; range = span |> span_to_range }
                              : Lsp.Types.SelectionRange.t))
                        None
                   |> Option.get)
            |> Linol_lwt.return
        | Some { ast = None; _ } | None -> Linol_lwt.return []

    method private on_format :
        notify_back:Linol_lwt.Jsonrpc2.notify_back ->
        Lsp.Types.DocumentFormattingParams.t ->
        Lsp.Types.TextEdit.t list option Lwt.t =
      fun ~notify_back:_ params ->
        Log.info "got format request";
        let { parsed; _ } = Hashtbl.find buffers params.textDocument.uri in
        match parsed with
        | None -> Linol_lwt.return None
        | Some parsed ->
            Kast_fmt.format Format.str_formatter parsed;
            let newText = Format.flush_str_formatter () in
            let result =
              Some
                [
                  ({
                     newText;
                     range =
                       {
                         start = { line = 0; character = 0 };
                         end_ = { line = 1000000000; character = 0 };
                       };
                   }
                    : Lsp.Types.TextEdit.t);
                ]
            in
            Linol_lwt.return result

    method private on_semantic_tokens :
        notify_back:Linol_lwt.Jsonrpc2.notify_back ->
        Lsp.Types.SemanticTokensParams.t ->
        Lsp.Types.SemanticTokens.t option Lwt.t =
      fun ~notify_back:_ params ->
        Log.info "got semantic tokens request";
        let { parsed; _ } = Hashtbl.find buffers params.textDocument.uri in
        match parsed with
        | None -> Linol_lwt.return None
        | Some { ast; trailing_comments; eof = _ } ->
            let data =
              let prev_pos = ref Position.beginning in
              let tokens =
                Seq.append
                  (ast |> Option.to_seq
                  |> Seq.flat_map (fun ast -> ast |> Tokens.collect))
                  (trailing_comments |> List.to_seq
                  |> Seq.map (fun (comment : Token.comment) : Tokens.token ->
                         { token = Comment comment.shape; span = comment.span })
                  )
              in
              tokens
              |> Seq.flat_map (fun ({ token; span } : Tokens.token) ->
                     let pos = ref <| linecol span.start in
                     Seq.of_dispenser (fun () ->
                         if !pos = linecol span.finish then None
                         else
                           let next_pos =
                             if !pos.line = span.finish.line then
                               linecol span.finish
                             else { line = !pos.line + 1; column = 1 }
                           in
                           (* we dont use index anyway *)
                           let fakepos (pos : linecol) : position =
                             { line = pos.line; column = pos.column; index = 0 }
                           in
                           let span : span =
                             {
                               start = fakepos !pos;
                               finish = fakepos next_pos;
                               filename = span.filename;
                             }
                           in
                           pos := next_pos;
                           Some span)
                     |> Seq.map (fun span : Tokens.token -> { token; span }))
              |> Seq.flat_map (fun ({ token; span } : Tokens.token) ->
                     let deltaLine = span.start.line - !prev_pos.line in
                     let deltaStartChar =
                       if deltaLine = 0 then
                         span.start.column - !prev_pos.column
                       else span.start.column - Position.beginning.column
                     in
                     let length =
                       if span.start.line = span.finish.line then
                         span.finish.column - span.start.column
                       else 1000 (* to the end of line :) *)
                     in
                     let tokenType =
                       match token with
                       | Tokens.Keyword _ -> Some 19 (* keyword *)
                       | Tokens.Value token -> (
                           match token with
                           | String _ -> Some 18 (* string *)
                           | Number _ -> Some 20
                           | _ -> None)
                       | Tokens.Comment _ -> Some 17
                       | Tokens.Unknown _ -> Some 15
                     in
                     let tokenModifiers = 0 in
                     let data =
                       tokenType
                       |> Option.map (fun tokenType ->
                              [
                                deltaLine;
                                deltaStartChar;
                                length;
                                tokenType;
                                tokenModifiers;
                              ])
                     in
                     (match data with
                     | Some data ->
                         Log.trace "@[<h>data: %a %a@]" (List.print Int.print)
                           data Span.print span;
                         prev_pos := span.start
                     | None -> ());
                     let data = data |> Option.value ~default:[] in
                     List.to_seq data)
              |> Array.of_seq
            in
            let tokens =
              Lsp.Types.SemanticTokens.create ~data ?resultId:None ()
            in
            Log.info "replied with semantic tokens";
            Linol_lwt.return <| Some tokens

    method! on_request_unhandled : type r.
        notify_back:Linol_lwt.Jsonrpc2.notify_back ->
        id:Linol.Server.Req_id.t ->
        r Lsp.Client_request.t ->
        r Lwt.t =
      fun ~notify_back ~id:_ request ->
        match request with
        | SelectionRange params -> self#on_selection_range ~notify_back params
        | TextDocumentFormatting params -> self#on_format ~notify_back params
        | SemanticTokensFull params ->
            self#on_semantic_tokens ~notify_back params
        | _ -> IO.failwith "TODO handle this request"
  end

let run ({ dummy = () } : Args.t) =
  Log.info "Starting Kast LSP";
  let s = new lsp_server in
  let server = Linol_lwt.Jsonrpc2.create_stdio ~env:() s in
  let task =
    let shutdown () = s#get_status = `ReceivedExit in
    Linol_lwt.Jsonrpc2.run ~shutdown server
  in
  match Linol_lwt.run task with
  | () ->
      Log.info "Exiting Kast LSP";
      ()
  | exception e -> raise e
