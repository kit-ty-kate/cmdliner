(*---------------------------------------------------------------------------
   Copyright (c) 2022 The cmdliner programmers. All rights reserved.
   Distributed under the ISC license, see terms at the end of the file.
  ---------------------------------------------------------------------------*)

module Exit = struct
  type code = int
  let ok = 0
  let some_error = 123
  let cli_error = 124
  let internal_error = 125

  type info = Cmdliner_info.exit
  let info = Cmdliner_info.exit
  let info_code i = fst (Cmdliner_info.exit_statuses i)

  let defaults =
    [ info ok ~doc:"on success.";
      info some_error ~doc:"on indiscriminate errors reported on stderr.";
      info cli_error ~doc:"on command line parsing errors.";
      info internal_error ~doc:"on unexpected internal errors (bugs)."; ]
end

module Env = struct
  type var = string
  type info = Cmdliner_info.env
  let info = Cmdliner_info.env
end

(* Commands *)

type info = Cmdliner_info.cmd
let info
    ?man_xrefs ?man ?envs ?(exits = Exit.defaults) ?sdocs ?docs ?doc ?version
    name
  =
  Cmdliner_info.cmd ~args:Cmdliner_info.Args.empty
    ?man_xrefs ?man ?envs ~exits ?sdocs ?docs ?doc ?version name

let info_name i = Cmdliner_info.cmd_name i

type 'a t =
| Cmd of info * 'a Cmdliner_term.parser
| Group of info * ('a Cmdliner_term.parser option * 'a t list)

let v i (args, p) = Cmd (Cmdliner_info.cmd_add_args i args, p)
let group ?default i cmds =
  let default, i = match default with
  | None -> None, i
  | Some (args, p) -> Some p, Cmdliner_info.cmd_add_args i args
  in
  Group (i, (default, cmds))

let get_info = function Cmd (i, _) | Group (i, _) -> i
let children_infos = function
| Cmd _ -> [] | Group (_, (_, cs)) -> List.map get_info cs

(* Eval *)

type 'a eval_ok = [ `Ok of 'a | `Version | `Help ]
type eval_error = [ `Parse | `Term | `Exn ]

let err_help s = "Term error, help requested for unknown command " ^ s
let err_argv = "argv array must have at least one element"

let add_stdopts ei =
  let docs = Cmdliner_info.(cmd_stdopts_docs @@ eval_cmd ei) in
  let vargs, vers = match Cmdliner_info.(cmd_version @@ eval_main ei) with
  | None -> Cmdliner_info.Args.empty, None
  | Some _ ->
      let args, _ as vers = Cmdliner_arg.stdopt_version ~docs in
      args, Some vers
  in
  let help = Cmdliner_arg.stdopt_help ~docs in
  let args = Cmdliner_info.Args.union vargs (fst help) in
  let cmd = Cmdliner_info.(cmd_add_args (eval_cmd ei) args) in
  help, vers, Cmdliner_info.eval_with_cmd ei cmd

let parse_error_term err ei cl = Error (`Parse err)

type 'a eval_result =
  ('a, [ Cmdliner_term.term_escape
       | `Exn of exn * Printexc.raw_backtrace
       | `Parse of string
       | `Std_help of Cmdliner_manpage.format | `Std_version ]) result

let run_parser ~catch ei cl f = try (f ei cl :> 'a eval_result) with
| exn when catch ->
    let bt = Printexc.get_raw_backtrace () in
    Error (`Exn (exn, bt))

let try_eval_stdopts ~catch ei cl help version =
  match run_parser ~catch ei cl (snd help) with
  | Ok (Some fmt) -> Some (Error (`Std_help fmt))
  | Error _ as err -> Some err
  | Ok None ->
      match version with
      | None -> None
      | Some version ->
          match run_parser ~catch ei cl (snd version) with
          | Ok false -> None
          | Ok true -> Some (Error (`Std_version))
          | Error _ as err -> Some err

let do_help help_ppf err_ppf ei fmt cmd =
  let ei = match cmd with
  | None -> Cmdliner_info.(eval_with_cmd ei @@ eval_main ei)
  | Some cmd ->
      try
        let is_cmd t = Cmdliner_info.cmd_name t = cmd in
        let cmd = List.find is_cmd (Cmdliner_info.eval_children ei) in
        Cmdliner_info.eval_with_cmd ei cmd
      with Not_found -> invalid_arg (err_help cmd)
  in
  let _, _, ei = add_stdopts ei (* may not be the originally eval'd term *) in
  Cmdliner_docgen.pp_man ~errs:err_ppf fmt help_ppf ei

let do_result help_ppf err_ppf ei = function
| Ok v -> Ok (`Ok v)
| Error res ->
    match res with
    | `Std_help fmt -> Cmdliner_docgen.pp_man err_ppf fmt help_ppf ei; Ok `Help
    | `Std_version -> Cmdliner_msg.pp_version help_ppf ei; Ok `Version
    | `Parse err ->
        Cmdliner_msg.pp_err_usage err_ppf ei ~err_lines:false ~err;
        Error `Parse
    | `Help (fmt, cmd) -> do_help help_ppf err_ppf ei fmt cmd; Ok `Help
    | `Exn (e, bt) -> Cmdliner_msg.pp_backtrace err_ppf ei e bt; (Error `Exn)
    | `Error (usage, err) ->
        (if usage
         then Cmdliner_msg.pp_err_usage err_ppf ei ~err_lines:true ~err
         else Cmdliner_msg.pp_err err_ppf ei ~err);
        (Error `Term)

let cmd_name_trie cmds =
  let add acc cmd =
    let i = get_info cmd in
    let name = Cmdliner_info.cmd_name i in
    match Cmdliner_trie.add acc name cmd with
    | `New t -> t
    | `Replaced (cmd', _) ->
        let i' = get_info cmd' and kind = "command" in
        invalid_arg @@
        Cmdliner_base.err_multi_def ~kind name Cmdliner_info.cmd_doc i i'
  in
  List.fold_left add Cmdliner_trie.empty cmds

let cmd_name_dom cmds =
  let cmd_name c = Cmdliner_info.cmd_name (get_info c) in
  List.sort String.compare (List.rev_map cmd_name cmds)

let find_term args cmd =
  let never_term _ _ = assert false in
  let stop args_rest args_rev parents cmd =
    let args = List.rev_append args_rev args_rest in
    match cmd with
    | Cmd (i, t) ->
        args, t, i, false, parents, [], Ok ()
    | Group (i, (Some t, children)) ->
        args, t, i, false, parents, children, Ok ()
    | Group (i, (None, children)) ->
        let err = Cmdliner_msg.err_cmd_missing in
        args, never_term, i, true, parents, children, Error err
  in
  let rec loop args_rev parents cmd = function
  | ("--" :: _ | [] as rest) -> stop rest args_rev parents cmd
  | (arg :: _ as rest) when Cmdliner_cline.is_opt arg ->
      stop rest args_rev parents cmd
  | arg :: args ->
      match cmd with
      | Cmd (i, t) ->
          let args = List.rev_append args_rev (arg :: args) in
          args, t, i, false, parents, [], Ok ()
      | Group (i, (t, children)) ->
          let index = cmd_name_trie children in
          match Cmdliner_trie.find index arg with
          | `Ok cmd -> loop args_rev (i :: parents) cmd args
          | `Not_found ->
              let args = List.rev_append args_rev (arg :: args) in
              let only_grouping = Option.is_none t in
              let all = Cmdliner_trie.ambiguities index "" in
              let hints = Cmdliner_base.suggest arg all in
              let dom = cmd_name_dom children in
              let kind = "command" in
              let err = Cmdliner_base.err_unknown ~kind ~dom ~hints arg in
              args, never_term, i, only_grouping, parents, children, Error err
          | `Ambiguous ->
              let args = List.rev_append args_rev (arg :: args) in
              let only_grouping = Option.is_none t in
              let ambs = Cmdliner_trie.ambiguities index arg in
              let ambs = List.sort compare ambs in
              let err = Cmdliner_base.err_ambiguous ~kind:"command" arg ~ambs in
              args, never_term, i, only_grouping, parents, children, Error err
  in
  loop [] [] cmd args

let env_default v = try Some (Sys.getenv v) with Not_found -> None
let remove_exec argv =
  try List.tl (Array.to_list argv) with Failure _ -> invalid_arg err_argv

let eval_value
    ?help:(help_ppf = Format.std_formatter)
    ?err:(err_ppf = Format.err_formatter)
    ?(catch = true) ?(env = env_default) ?(argv = Sys.argv) cmd
  =
  let args, f, i, only_grouping, parents, children, res =
    find_term (remove_exec argv) cmd
  in
  let children = List.map get_info children in
  let ei = Cmdliner_info.eval ~cmd:i ~only_grouping ~parents ~children ~env in
  let help, version, ei = add_stdopts ei in
  let term_args = Cmdliner_info.(cmd_args @@ eval_cmd ei) in
  let res = match res with
  | Error msg -> (* Command lookup error, we still prioritize stdargs *)
      let cl = match Cmdliner_cline.create term_args args with
      | Error (_, cl) -> cl | Ok cl -> cl
      in
      begin match try_eval_stdopts ~catch ei cl help version with
      | Some e -> e
      | None -> Error (`Error (true, msg))
      end
  | Ok () ->
      match Cmdliner_cline.create term_args args with
      | Error (e, cl) ->
          begin match try_eval_stdopts ~catch ei cl help version with
          | Some e -> e
          | None -> Error (`Error (true, e))
          end
      | Ok cl ->
          match try_eval_stdopts ~catch ei cl help version with
          | Some e -> e
          | None -> run_parser ~catch ei cl f
  in
  do_result help_ppf err_ppf ei res

let eval_peek_opts
    ?(version_opt = false) ?(env = env_default) ?(argv = Sys.argv) t
  : 'a option * ('a eval_ok, eval_error) result
  =
  let args, f = t in
  let version = if version_opt then Some "dummy" else None in
  let cmd = Cmdliner_info.cmd ~args ?version "dummy" in
  let ei =
    Cmdliner_info.eval ~cmd ~only_grouping:false ~parents:[] ~children:[]
      ~env
  in
  let help, version, ei = add_stdopts ei in
  let term_args = Cmdliner_info.(cmd_args @@ eval_cmd ei) in
  let cli_args =  remove_exec argv in
  let v, ret =
    match Cmdliner_cline.create ~peek_opts:true term_args cli_args with
    | Error (e, cl) ->
        begin match try_eval_stdopts ~catch:true ei cl help version with
        | Some e -> None, e
        | None -> None, Error (`Error (true, e))
        end
    | Ok cl ->
        let ret = run_parser ~catch:true ei cl f in
        let v = match ret with Ok v -> Some v | Error _ -> None in
        match try_eval_stdopts ~catch:true ei cl help version with
        | Some e -> v, e
        | None -> v, ret
  in
  let ret = match ret with
  | Ok v -> Ok (`Ok v)
  | Error `Std_help _ -> Ok `Help
  | Error `Std_version -> Ok `Version
  | Error `Parse _ -> Error `Parse
  | Error `Help _ -> Ok `Help
  | Error `Exn _ -> Error `Exn
  | Error `Error _ -> Error `Term
  in
  (v, ret)

let exit_status_of_result ?(term_err = Exit.cli_error) = function
| Ok (`Ok _ | `Help | `Version) -> Exit.ok
| Error `Term -> term_err
| Error `Parse -> Exit.cli_error
| Error `Exn -> Exit.internal_error

let eval ?help ?err ?catch ?env ?argv ?term_err cmd =
  exit_status_of_result ?term_err @@
  eval_value ?help ?err ?catch ?env ?argv cmd

let eval' ?help ?err ?catch ?env ?argv ?term_err cmd =
  match eval_value ?help ?err ?catch ?env ?argv cmd with
  | Ok (`Ok c) -> c
  | r -> exit_status_of_result ?term_err r

let pp_err ppf cmd ~msg = (* FIXME move that to Cmdliner_msgs *)
  let name = info_name (get_info cmd) in
  Format.fprintf  ppf "%s: @[%a@]@." name Cmdliner_base.pp_lines msg

let eval_result
    ?help ?(err = Format.err_formatter) ?catch ?env ?argv ?term_err cmd
  =
  match eval_value ?help ~err ?catch ?env ?argv cmd with
  | Ok (`Ok (Error msg)) -> pp_err err cmd ~msg; Exit.some_error
  | r -> exit_status_of_result ?term_err r

let eval_result'
    ?help ?(err = Format.err_formatter) ?catch ?env ?argv ?term_err cmd
  =
  match eval_value ?help ~err ?catch ?env ?argv cmd with
  | Ok (`Ok (Ok c)) -> c
  | Ok (`Ok (Error msg)) -> pp_err err cmd ~msg; Exit.some_error
  | r -> exit_status_of_result ?term_err r

(*---------------------------------------------------------------------------
   Copyright (c) 2022 The cmdliner programmers

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
