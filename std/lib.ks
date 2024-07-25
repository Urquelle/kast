# BrainoidGames: do you have type casting yet? if not, can we name it kast()?

syntax builtin_macro_then <- 0 = a ";" b;
syntax builtin_macro_then <- 0 = a ";";

syntax break_with_value <- 2 = "break" value;
syntax break_without_value <- 2 = "break";
syntax continue_impl <- 2 = "continue";

syntax builtin_macro_create_impl <- 3 = "impl" trait "for" value "as" impl;
syntax builtin_macro_let <- 4 = "let" pattern "=" value;
syntax builtin_macro_const_let <- 4 = "const" pattern "=" value;

syntax builtin_macro_tuple <- 4.5 = a "," b;
syntax builtin_macro_tuple <- 4.5 = a ",";

syntax builtin_macro_field <- 4.75 = name ":" value;
syntax inline_field <- 4.75 = "~" name;
syntax inline_typed_field <- 4.75 = "~" name "::" type;

syntax builtin_macro_unwindable_block <- 5 = "unwindable_block" def;
syntax builtin_macro_with_context <- 5 = "with" new_context "(" expr ")";
syntax builtin_macro_current_context <- 5 = "current" context_type;
syntax builtin_fn_macro <- 5 = "macro" def;
syntax comptime <- 5 = "comptime" value;
syntax builtin_macro_oneof <- 5 = "oneof" def;

syntax builtin_macro_combine_variants <- 6 = "|" a;
syntax builtin_macro_combine_variants <- 6 = a "|" b;
syntax builtin_macro_function_def -> 7 = args "=>" body;

syntax builtin_macro_type_ascribe <- 7.1 = value "::" type;

syntax builtin_fn_function_type -> 7.5 = arg "->" result;
syntax builtin_fn_function_type -> 7.5 = arg "->" result "incontext" contexts;
syntax builtin_macro_function_def -> 7.5 = args "->" returns "=>" body;

syntax builtin_macro_single_variant -> 8 = name "of" type;
syntax builtin_macro_single_variant -> 8 = name "ofnone";

syntax builtin_macro_template_def <- 9 = "forall" args "." body;
syntax builtin_macro_template_def <- 9 = "forall" args "where" where "." body;

syntax builtin_macro_match <- 13 = "match" value "(" branches ")";
syntax builtin_macro_if <- 13 = "if" cond "then" then;
syntax builtin_macro_if <- 13 = "if" cond "then" then "else" else;
syntax builtin_macro_if -> 13 = cond "?" then ":" else;
syntax builtin_macro_if -> 13 = cond "then" then "else" else;

syntax implements <- 14 = type "implements" trait;

syntax pipe <- 15 = args "|>" f;
syntax pipe <- 15 = f "<|" args;

syntax catch_impl <- 16 = expr "catch" e "{" catch_block "}";

syntax builtin_fn_or <- 17 = lhs "or" rhs;
syntax builtin_fn_and <- 18 = lhs "and" rhs;

syntax @"op binary <" <- 19 = lhs "<" rhs;
syntax @"op binary <=" <- 19 = lhs "<=" rhs;
syntax @"op binary ==" <- 19 = lhs "==" rhs;
syntax @"op binary !=" <- 19 = lhs "!=" rhs;
syntax @"op binary >=" <- 19 = lhs ">=" rhs;
syntax @"op binary >" <- 19 = lhs ">" rhs;

syntax builtin_macro_get_impl <- 20 = value "as" trait;
syntax builtin_macro_check_impl <- 20 = value "impl" trait;

syntax @"op unary +" <- 25 = "+" x;
syntax @"op unary -" <- 25 = "-" x;
syntax @"op binary +" <- 25 = lhs "+" rhs;
syntax @"op binary -" <- 25 = lhs "-" rhs;

syntax @"op binary *" <- 40 = lhs "*" rhs;
syntax @"op binary /" <- 40 = lhs "/" rhs;
syntax @"op binary %" <- 40 = lhs "%" rhs;

syntax @"op binary ^" -> 60 = lhs "^" rhs;

syntax builtin_macro_call <- 100 = f args;

syntax builtin_macro_typeof <- 120 = "typeof" expr;
syntax builtin_macro_typeofvalue <- 120 = "typeofvalue" expr;

syntax builtin_macro_instantiate_template <- 150 = template "[" args "]";

syntax builtin_macro_quote -> 200 = "`" expr;
syntax builtin_macro_quote -> 200 = "`" "(" expr ")";
syntax builtin_macro_unquote -> 200 = "$" expr;
syntax builtin_macro_unquote -> 200 = "$" "(" expr ")";

syntax builtin_macro_field_access <- 300 = obj "." field;

syntax builtin_macro_struct_def <- 500 = "struct" "(" body ")";
syntax builtin_macro_function_def <- 500 = "fn" "(" args ")" contexts "{" body "}";
syntax builtin_macro_function_def <- 500 = "fn" "(" args ")" "->" result_type "{" body "}";
syntax builtin_macro_function_def <- 500 = "fn" "(" args ")" "{" body "}";
syntax builtin_macro_function_def <- 100000 = "(" args ")" "{" body "}";
syntax builtin_macro_function_def <- 100000 = "(" ")" "{" body "}";
syntax builtin_macro_function_def <- 100000 = "{" body "}";

syntax builtin_macro_scope <- 100000 = "(" e ")";
syntax builtin_macro_make_void <- 100000 = "(" ")";
syntax builtin_macro_placeholder <- 100000 = "_";

let Option = forall (T :: type). (Some of T | None ofnone);
let Either = forall ((~left, ~right) :: ( left: type, right: type )). (Left of left | Right of right);
let Result = forall ((~ok, ~error) :: ( ok: type, error: type)). (Ok of ok | Error of error);

const inline_field = macro (name : name) => `($name : $name);
const inline_typed_field = macro (~name, ~type) :: (name: ast, type: ast) => `(
    $name: ($name :: $type)
);


# args |> f
const pipe = macro (~f, ~args) => `((
    $f $args
));

let input :: void -> string = () => builtin_fn_input ();
let print :: string -> void = s => builtin_fn_print s;

let loop_context :: type = (
    finish_current_iteration: (bool -> never), # todo should be option[T] -> never
) as type;

# todo
# with = forall (arg :: type, result :: type, old_context :: type, new_context :: type).
# fn (body :: arg -> result incontext (old_context and new_context)) old_context {
# body arg
# }

let dbg = forall (T :: type). ((x :: T) -> void => builtin_fn_dbg x);

let unwind = forall (T :: type). (
    (args => builtin_fn_unwind args) :: (token: unwind_token, value: T) -> never
);

let loop = fn (body :: (void -> void incontext loop_context)) {
    let should_continue = unwindable_block (token :: unwind_token) {
        let current_loop_context = (
            finish_current_iteration: (x :: bool) -> never => unwind ( ~token, value: x ),
        );
        with current_loop_context (
            body ();
            true
        )
    };
    if should_continue then (loop body);
};

let do_break = fn (value :: void) loop_context {
    (current loop_context).finish_current_iteration false
};

let do_continue = fn (void) loop_context {
    (current loop_context).finish_current_iteration true
};

let continue_impl = macro (args :: any) => (
    `(do_continue ())
);

let break_without_value = macro _ => `(do_break void);
let break_with_value = macro (~value) => `(do_break $value);

let throws = forall (error :: type). (throw: (error -> never));
let throw = forall (error :: type). (
	fn (e :: error) {
		(current throws[error]).throw e
	}
);

let try = forall
		(~ok :: type, ~error :: type). (
	fn (body :: (void -> ok incontext throws[error])) {
		unwindable_block (token :: unwind_token) {
			const result_type = Result[~ok, ~error];
			let throw_context = throw: (e :: error => unwind (~token, value: result_type.Error e));
			with throw_context (
			 	body () |> result_type.Ok
			)
		}
	}
);

let catch_impl = macro (~expr :: ast, ~e :: ast, ~catch_block :: ast) => `(
	match $expr (
		| Ok of value => value
		| Error of $e => $catch_block
	)
);

let random = forall (T :: type). (
    (
    if builtin_fn_is_same_type (a: T, b: int32) then
        (args => builtin_fn_random_int32 args)
    else (if builtin_fn_is_same_type (a: T, b: float64) then
        (args => builtin_fn_random_float64 args)
    else
        builtin_fn_panic "wtf")
    ) :: (min: T, max: T) -> T
);

const TypeName :: type = (
    name: string
) as type;

impl TypeName for void as (
    name: "void",
);

impl TypeName for type as (
    name: "type",
);

impl TypeName for bool as (
    name: "bool",
);

impl TypeName for int32 as (
    name: "int32",
);

impl TypeName for int64 as (
    name: "int64",
);

impl TypeName for float32 as (
    name: "float32",
);

impl TypeName for float64 as (
    name: "float64",
);

impl TypeName for string as (
    name: "string",
);

let type_name = forall (T :: type) where (T impl TypeName). (
    (T as TypeName).name
);

const Eq = forall (T :: type). (
    eq: (lhs: T, rhs: T) -> bool
);

impl Eq for int32 as (
    eq: args => @"builtin_fn_==" args
);

impl Eq for string as (
    eq: args => @"builtin_fn_==" args
);

let @"op binary ==" = macro (~lhs, ~rhs) => `(
    (_ as Eq).eq(lhs: $lhs, rhs: $rhs)
);

let @"op binary +" :: (lhs: int32, rhs: int32) -> int32 = args => @"builtin_fn_binary +" args;
let @"op binary -" :: (lhs: int32, rhs: int32) -> int32 = args => @"builtin_fn_binary -" args;

let @"op binary <" :: (lhs: int32, rhs: int32) -> bool = args => @"builtin_fn_<" args;

const Parse = forall (Self :: type). (
    parse: (string -> Self),
);

impl Parse for int32 as (
    parse: (s => builtin_fn_string_to_int32 s),
);

impl Parse for float64 as (
    parse: (s => builtin_fn_string_to_float64 s),
);

let parse = forall (T :: type) where (T impl Parse). (
    (T as Parse).parse
);

let sin :: float64 -> float64 = x => builtin_fn_sin x;

()

