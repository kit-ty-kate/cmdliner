(*---------------------------------------------------------------------------
   Copyright (c) 2011 The cmdliner programmers. All rights reserved.
   Distributed under the ISC license, see terms at the end of the file.
  ---------------------------------------------------------------------------*)


let new_id =
  (* thread-safe UIDs, Oo.id (object end) was used before.
     Note this won't be thread-safe in multicore, we should use
     Atomic but this is >= 4.12 and we have 4.08 for now. *)
  let c = ref 0 in
  fun () ->
    let id = !c in
    incr c; if id > !c then assert false (* too many ids *) else id

(* Environments *)

type env =                     (* information about an environment variable. *)
  { env_id : int;                              (* unique id for the env var. *)
    env_var : string;                                       (* the variable. *)
    env_doc : string;                                               (* help. *)
    env_docs : string; }              (* title of help section where listed. *)

let env
    ?docs:(env_docs = Cmdliner_manpage.s_environment)
    ?doc:(env_doc = "See option $(opt).") env_var =
  { env_id = new_id (); env_var; env_doc; env_docs }

let env_var e = e.env_var
let env_doc e = e.env_doc
let env_docs e = e.env_docs

module Env = struct
  type t = env
  let compare a0 a1 = (compare : int -> int -> int) a0.env_id a1.env_id
end

module Envs = Set.Make (Env)
type envs = Envs.t

(* Arguments *)

type arg_absence = Err | Val of string Lazy.t
type opt_kind = Flag | Opt | Opt_vopt of string

type pos_kind =                  (* information about a positional argument. *)
  { pos_rev : bool;         (* if [true] positions are counted from the end. *)
    pos_start : int;                           (* start positional argument. *)
    pos_len : int option }    (* number of arguments or [None] if unbounded. *)

let pos ~rev:pos_rev ~start:pos_start ~len:pos_len =
  { pos_rev; pos_start; pos_len}

let pos_rev p = p.pos_rev
let pos_start p = p.pos_start
let pos_len p = p.pos_len

type arg =                     (* information about a command line argument. *)
  { id : int;                                 (* unique id for the argument. *)
    absent : arg_absence;                            (* behaviour if absent. *)
    env : env option;                               (* environment variable. *)
    doc : string;                                                   (* help. *)
    docv : string;                (* variable name for the argument in help. *)
    docs : string;                    (* title of help section where listed. *)
    pos : pos_kind;                                  (* positional arg kind. *)
    opt_kind : opt_kind;                               (* optional arg kind. *)
    opt_names : string list;                        (* names (for opt args). *)
    opt_all : bool; }                          (* repeatable (for opt args). *)

let dumb_pos = pos ~rev:false ~start:(-1) ~len:None

let arg ?docs ?(docv = "") ?(doc = "") ?env names =
  let dash n = if String.length n = 1 then "-" ^ n else "--" ^ n in
  let opt_names = List.map dash names in
  let docs = match docs with
  | Some s -> s
  | None ->
      match names with
      | [] -> Cmdliner_manpage.s_arguments
      | _ -> Cmdliner_manpage.s_options
  in
  { id = new_id (); absent = Val (lazy ""); env; doc; docv; docs;
    pos = dumb_pos; opt_kind = Flag; opt_names; opt_all = false; }

let arg_id a = a.id
let arg_absent a = a.absent
let arg_env a = a.env
let arg_doc a = a.doc
let arg_docv a = a.docv
let arg_docs a = a.docs
let arg_pos a = a.pos
let arg_opt_kind a = a.opt_kind
let arg_opt_names a = a.opt_names
let arg_opt_all a = a.opt_all
let arg_opt_name_sample a =
  (* First long or short name (in that order) in the list; this
     allows the client to control which name is shown *)
  let rec find = function
  | [] -> List.hd a.opt_names
  | n :: ns -> if (String.length n) > 2 then n else find ns
  in
  find a.opt_names

let arg_make_req a = { a with absent = Err }
let arg_make_all_opts a = { a with opt_all = true }
let arg_make_opt ~absent ~kind:opt_kind a = { a with absent; opt_kind }
let arg_make_opt_all ~absent ~kind:opt_kind a =
  { a with absent; opt_kind; opt_all = true  }

let arg_make_pos ~pos a = { a with pos }
let arg_make_pos_abs ~absent ~pos a = { a with absent; pos }

let arg_is_opt a = a.opt_names <> []
let arg_is_pos a = a.opt_names = []
let arg_is_req a = a.absent = Err

let arg_pos_cli_order a0 a1 =              (* best-effort order on the cli. *)
  let c = compare (a0.pos.pos_rev) (a1.pos.pos_rev) in
  if c <> 0 then c else
  if a0.pos.pos_rev
  then compare a1.pos.pos_start a0.pos.pos_start
  else compare a0.pos.pos_start a1.pos.pos_start

let rev_arg_pos_cli_order a0 a1 = arg_pos_cli_order a1 a0

module Arg = struct
  type t = arg
  let compare a0 a1 = (compare : int -> int -> int) a0.id a1.id
end

module Args = Set.Make (Arg)
type args = Args.t

(* Exit info *)

type exit =
  { exit_statuses : int * int;
    exit_doc : string;
    exit_docs : string; }

let exit
    ?docs:(exit_docs = Cmdliner_manpage.s_exit_status)
    ?doc:(exit_doc = "undocumented") ?max min =
  let max = match max with None -> min | Some max -> max in
  { exit_statuses = (min, max); exit_doc; exit_docs }

let exit_statuses e = e.exit_statuses
let exit_doc e = e.exit_doc
let exit_docs e = e.exit_docs
let exit_order e0 e1 = compare e0.exit_statuses e1.exit_statuses

(* Command info *)

type cmd_info =
  { cmd_name : string;                                  (* name of the cmd. *)
    cmd_version : string option;                (* version (for --version). *)
    cmd_doc : string;                      (* one line description of term. *)
    cmd_docs : string;     (* title of man section where listed (commands). *)
    cmd_sdocs : string; (* standard options, title of section where listed. *)
    cmd_exits : exit list;                      (* exit codes for the term. *)
    cmd_envs : env list;               (* env vars that influence the term. *)
    cmd_man : Cmdliner_manpage.block list;                (* man page text. *)
    cmd_man_xrefs : Cmdliner_manpage.xref list; }        (* man cross-refs. *)

type cmd =
  { cmd_info : cmd_info;
    cmd_args : args; }

let cmd
    ?args:(cmd_args = Args.empty) ?man_xrefs:(cmd_man_xrefs = [])
    ?man:(cmd_man = []) ?envs:(cmd_envs = []) ?exits:(cmd_exits = [])
    ?sdocs:(cmd_sdocs = Cmdliner_manpage.s_options)
    ?docs:(cmd_docs = "COMMANDS") ?doc:(cmd_doc = "") ?version:cmd_version
    cmd_name =
  let cmd_info =
    { cmd_name; cmd_version; cmd_doc; cmd_docs; cmd_sdocs; cmd_exits;
      cmd_envs; cmd_man; cmd_man_xrefs }
  in
  { cmd_info; cmd_args }

let cmd_name t = t.cmd_info.cmd_name
let cmd_version t = t.cmd_info.cmd_version
let cmd_doc t = t.cmd_info.cmd_doc
let cmd_docs t = t.cmd_info.cmd_docs
let cmd_stdopts_docs t = t.cmd_info.cmd_sdocs
let cmd_exits t = t.cmd_info.cmd_exits
let cmd_envs t = t.cmd_info.cmd_envs
let cmd_man t = t.cmd_info.cmd_man
let cmd_man_xrefs t = t.cmd_info.cmd_man_xrefs
let cmd_args t = t.cmd_args

let cmd_add_args t args =
  { t with cmd_args = Args.union args t.cmd_args }

(* Eval info *)

type eval =                     (* information about the evaluation context. *)
  { cmd : cmd;                                    (* cmd being evaluated. *)
    only_grouping : bool;             (* cmd groups, has no cli on its own. *)
    parents : cmd list;   (* parents of cmd, last element is program info. *)
    children : cmd list;                   (* children if cmd is grouping. *)
    env : string -> string option }          (* environment variable lookup. *)

let eval ~cmd ~only_grouping ~parents ~children ~env =
  { cmd; only_grouping; parents; children; env }
let eval_cmd e = e.cmd
let eval_only_grouping e = e.only_grouping
let eval_parents e = e.parents
let eval_children e = e.children
let eval_env_var e v = e.env v
let eval_main e =
  if e.parents = [] then e.cmd else (List.hd @@ List.rev e.parents)

let eval_cmd_names e = List.rev_map cmd_name (e.cmd :: e.parents)
let eval_with_cmd ei cmd = { ei with cmd }
let eval_has_choice e cmd =
  let is_cmd t = t.cmd_info.cmd_name = cmd in
  List.exists is_cmd e.children

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
