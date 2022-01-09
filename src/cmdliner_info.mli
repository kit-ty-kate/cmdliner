(*---------------------------------------------------------------------------
   Copyright (c) 2011 The cmdliner programmers. All rights reserved.
   Distributed under the ISC license, see terms at the end of the file.
  ---------------------------------------------------------------------------*)

(** Terms, argument, env vars information.

    The following types keep untyped information about arguments and
    terms. This data is used to parse the command line, report errors
    and format man pages. *)

(** {1:env Environment variables} *)

type env
val env : ?docs:string -> ?doc:string -> string -> env
val env_var : env -> string
val env_doc : env -> string
val env_docs : env -> string

module Env : Set.OrderedType with type t = env
module Envs : Set.S with type elt = env
type envs = Envs.t

(** {1:arg Arguments} *)

type arg_absence =
| Err  (** an error is reported. *)
| Val of string Lazy.t (** if <> "", takes the given default value. *)
(** The type for what happens if the argument is absent from the cli. *)

type opt_kind =
| Flag (** without value, just a flag. *)
| Opt  (** with required value. *)
| Opt_vopt of string (** with optional value, takes given default. *)
(** The type for optional argument kinds. *)

type pos_kind
val pos : rev:bool -> start:int -> len:int option -> pos_kind
val pos_rev : pos_kind -> bool
val pos_start : pos_kind -> int
val pos_len : pos_kind -> int option

type arg
val arg :
  ?docs:string -> ?docv:string -> ?doc:string -> ?env:env ->
  string list -> arg

val arg_id : arg -> int
val arg_absent : arg -> arg_absence
val arg_env : arg -> env option
val arg_doc : arg -> string
val arg_docv : arg -> string
val arg_docs : arg -> string
val arg_opt_names : arg -> string list (* has dashes *)
val arg_opt_name_sample : arg -> string (* warning must be an opt arg *)
val arg_opt_kind : arg -> opt_kind
val arg_pos : arg -> pos_kind

val arg_make_req : arg -> arg
val arg_make_all_opts : arg -> arg
val arg_make_opt : absent:arg_absence -> kind:opt_kind -> arg -> arg
val arg_make_opt_all : absent:arg_absence -> kind:opt_kind -> arg -> arg
val arg_make_pos : pos:pos_kind -> arg -> arg
val arg_make_pos_abs : absent:arg_absence -> pos:pos_kind -> arg -> arg

val arg_is_opt : arg -> bool
val arg_is_pos : arg -> bool
val arg_is_req : arg -> bool

val arg_pos_cli_order : arg -> arg -> int
val rev_arg_pos_cli_order : arg -> arg -> int

module Arg : Set.OrderedType with type t = arg
module Args : Set.S with type elt = arg
type args = Args.t

(** {1:exit Exit status} *)

type exit
val exit : ?docs:string -> ?doc:string -> ?max:int -> int -> exit
val exit_statuses : exit -> int * int
val exit_doc : exit -> string
val exit_docs : exit -> string
val exit_order : exit -> exit -> int

(** {1:cmd Command information} *)

type cmd

val cmd :
  ?args:args -> ?man_xrefs:Cmdliner_manpage.xref list ->
  ?man:Cmdliner_manpage.block list -> ?envs:env list -> ?exits:exit list ->
  ?sdocs:string -> ?docs:string -> ?doc:string -> ?version:string ->
  string -> cmd

val cmd_name : cmd -> string
val cmd_version : cmd -> string option
val cmd_doc : cmd -> string
val cmd_docs : cmd -> string
val cmd_stdopts_docs : cmd -> string
val cmd_exits : cmd -> exit list
val cmd_envs : cmd -> env list
val cmd_man : cmd -> Cmdliner_manpage.block list
val cmd_man_xrefs : cmd -> Cmdliner_manpage.xref list
val cmd_args : cmd -> args
val cmd_add_args : cmd -> args -> cmd

(** {1:eval Evaluation information} *)

type eval

val eval :
  cmd:cmd -> only_grouping:bool -> parents:cmd list -> children:cmd list ->
  env:(string -> string option) -> eval

val eval_cmd : eval -> cmd
val eval_only_grouping : eval -> bool
val eval_main : eval -> cmd
val eval_children : eval -> cmd list
val eval_parents : eval -> cmd list
val eval_env_var : eval -> string -> string option
val eval_cmd_names : eval -> string list
val eval_with_cmd : eval -> cmd -> eval
val eval_has_choice : eval -> string -> bool

(*---------------------------------------------------------------------------
   Copyright (c) 2011 The cmdliner programmers

   Permission to use, copy, modify, and/or distribute this software for any
   purpose with or without fee is hereby granted, provided that the above
   copyright notice and this permission notice appear in all copies.

   THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
   WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
   MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
   ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
   WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
   ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
   OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
  ---------------------------------------------------------------------------*)
