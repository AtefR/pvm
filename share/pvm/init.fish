if not set -q PVM_PROJECT_ROOT
    set -l source_file (status filename)
    if test -n "$source_file"
        set -gx PVM_PROJECT_ROOT (path dirname (path dirname $source_file))
    end
end

if not set -q PVM_DIR
    set -gx PVM_DIR "$HOME/.pvm"
end
set -gx PVM_SHIMS_DIR "$PVM_DIR/shims"
set -gx PVM_SHELL_LOADED fish

if not contains -- $PVM_SHIMS_DIR $PATH
    set -gx PATH $PVM_SHIMS_DIR $PATH
end

function __pvm_bin
    if set -q PVM_PROJECT_ROOT; and test -x "$PVM_PROJECT_ROOT/bin/pvm"
        echo "$PVM_PROJECT_ROOT/bin/pvm"
        return 0
    end

    if test -x "$HOME/.local/bin/pvm"
        echo "$HOME/.local/bin/pvm"
        return 0
    end

    return 1
end

function __pvm_apply_env
    set -l pvm_bin (__pvm_bin)
    or return 1

    set -l output (env PVM_EVAL=1 PVM_SHELL=fish $pvm_bin env $argv)
    set -l cmd_status $status
    if test $cmd_status -ne 0
        return $cmd_status
    end

    if test (count $output) -gt 0
        eval (string join ';' -- $output)
    end
end

function __pvm_install_wrapper
    set -l pvm_bin (__pvm_bin)
    or return 1
    set -l target
    set -l use_after 0
    set -l install_args

    for arg in $argv
        if test "$arg" = "--use"
            set use_after 1
            continue
        end

        set install_args $install_args $arg
        if not string match -qr '^-' -- $arg; and test "$arg" != "install"; and test -z "$target"
            set target $arg
        end
    end

    $pvm_bin $install_args
    set -l cmd_status $status
    if test $cmd_status -ne 0
        return $cmd_status
    end

    if test $use_after -eq 1
        __pvm_apply_env use $target
    end
end

function pvm
    set -l command_name $argv[1]
    set -l pvm_bin (__pvm_bin)
    or return 1

    switch $command_name
        case use shell
            set -e argv[1]
            __pvm_apply_env use $argv
        case deactivate
            __pvm_apply_env deactivate
        case install
            __pvm_install_wrapper $argv
        case '*'
            $pvm_bin $argv
    end
end
