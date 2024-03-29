# bash completion for yum

_yum_helper()
{
    local IFS=$'\n'
    if [[ -n "$YUM_CACHEDIR" && "$1 $2" == "list available" ]]; then
        for db in $(find "$YUM_CACHEDIR" -name primary_db.sqlite); do
            COMPREPLY+=( $( sqlite3 "$db" \
                "SELECT name||'.'||arch FROM packages WHERE name LIKE '$3%'"
            ) )
        done
        return
    fi
    COMPREPLY+=( $(
        /usr/share/yum-cli/completion-helper.py -d 0 -C "$@" 2>/dev/null ) )
}

_yum_list()
{
    # Fail fast for things that look like paths or options.
    [[ $2 == */* || $2 == [.~-]* ]] && return
    # Listing all available packages takes way too long
    [[ $1 != "installed" && ${#2} -lt 1 ]] && return
    _yum_helper list "$@"
}

# arguments:
#   1 = 1 or 0 to list enabled or disabled plugins
#   2 = current word to be completed
_yum_plugins()
{
    local val
    [[ $1 -eq 1 ]] && val='\(1\|yes\|true\|on\)' || val='\(0\|no\|false\|off\)'
    COMPREPLY+=( $( compgen -W '$( command grep -il "^\s*enabled\s*=\s*$val" \
        /etc/yum/pluginconf.d/*.conf 2>/dev/null \
        | sed -ne "s|^.*/\([^/]\{1,\}\)\.conf$|\1|p" )' -- "$2" ) )
}

# arguments:
#   1 = current word to be completed
_yum_binrpmfiles()
{
    local IFS=$'\n'
    COMPREPLY+=( $( compgen -f -o plusdirs -X '!*.rpm' -- "$1" ) )
    COMPREPLY=( $( compgen -W '"${COMPREPLY[@]}"' -X '*.src.rpm' ) )
    COMPREPLY=( $( compgen -W '"${COMPREPLY[@]}"' -X '*.nosrc.rpm' ) )
}

_yum_baseopts()
{
    local opts='--help --tolerant --cacheonly --config --randomwait
        --debuglevel --showduplicates --errorlevel --rpmverbosity --quiet
        --verbose --assumeyes --assumeno --version --installroot --enablerepo
        --disablerepo --exclude --disableexcludes --obsoletes --noplugins
        --nogpgcheck --skip-broken --color --releasever --setopt --downloadonly
        --downloaddir --disableincludes'
    [[ $COMP_LINE == *--noplugins* ]] || \
        opts+=" --disableplugin --enableplugin"
    printf %s "$opts"
}

_yum_transactions()
{
    COMPREPLY+=( $( compgen -W "$( $yum -d 0 -C history 2>/dev/null | \
        sed -ne 's/^[[:space:]]*\([0-9]\{1,\}\).*/\1/p' )" -- "$cur" ) )
}

_yum_atgroups()
{
    if [[ $1 == \@* ]]; then
        _yum_helper groups list all "${1:1}"
        COMPREPLY=( "${COMPREPLY[@]/#/@}" )
        return 0
    fi
    return 1
}

# arguments:
#   1 = current word to be completed
#   2 = previous word
# return 0 if no more completions should be sought, 1 otherwise
_yum_complete_baseopts()
{
    case $2 in

        -d|--debuglevel|-e|--errorlevel)
            COMPREPLY=( $( compgen -W '0 1 2 3 4 5 6 7 8 9 10' -- "$1" ) )
            return 0
            ;;

        --rpmverbosity)
            COMPREPLY=( $( compgen -W 'info critical emergency error warn
                debug' -- "$1" ) )
            return 0
            ;;

        -c|--config)
            local IFS=$'\n'
            COMPREPLY=( $( compgen -f -o plusdirs -X "!*.conf" -- "$1" ) )
            return 0
            ;;

        --installroot|--downloaddir)
            local IFS=$'\n'
            COMPREPLY=( $( compgen -d -- "$1" ) )
            return 0
            ;;

        --enablerepo)
            _yum_helper repolist disabled "$1"
            return 0
            ;;

        --disablerepo)
            _yum_helper repolist enabled "$1"
            return 0
            ;;

        --disableexcludes|--disableincludes)
            _yum_helper repolist all "$1"
            local main=
            [[ $2 == *excludes ]] && main=main
            COMPREPLY=( $( compgen -W '${COMPREPLY[@]} all $main' -- "$1" ) )
            return 0
            ;;

        --enableplugin)
            _yum_plugins 0 "$1"
            return 0
            ;;

        --disableplugin)
            _yum_plugins 1 "$1"
            return 0
            ;;

        --color)
            COMPREPLY=( $( compgen -W 'always auto never' -- "$1" ) )
            return 0
            ;;

        -R|--randomwait|-x|--exclude|-h|--help|--version|--releasever|--cve|\
        --bz|--advisory|--tmprepo|--verify-filenames|--setopt)
            return 0
            ;;

        --download-order)
            COMPREPLY=( $( compgen -W 'default smallestfirst largestfirst' \
                -- "$1" ) )
            return 0
            ;;

        --override-protection)
            _yum_list installed "$1"
            return 0
            ;;

        --verify-configuration-files)
            COMPREPLY=( $( compgen -W '1 0' -- "$1" ) )
            return 0
            ;;
    esac

    return 1
}

_yum()
{
    COMPREPLY=()
    local yum=$1 cur=$2 prev=$3 words=("${COMP_WORDS[@]}")
    declare -F _get_comp_words_by_ref &>/dev/null && \
        _get_comp_words_by_ref -n = cur prev words

    # Commands offered as completions
    local cmds=( autoremove check check-update clean deplist distro-sync downgrade
        erase groups help history info install list load-transaction makecache provides
        reinstall remove repolist search shell update upgrade version )

    local i c cmd subcmd
    for (( i=1; i < ${#words[@]}-1; i++ )) ; do
        [[ -n $cmd ]] && subcmd=${words[i]} && break
        # Recognize additional commands and aliases
        for c in ${cmds[@]} check-rpmdb distribution-synchronization erase \
            group groupinfo groupinstall grouplist groupremove groupupdate \
            grouperase install-na load-ts localinstall localupdate whatprovides ; do
            [[ ${words[i]} == $c ]] && cmd=$c && break
        done
    done

    case $cmd in

        autoremove|erase|remove)
            _yum_atgroups "$cur" || _yum_list installed "$cur"
            return 0
            ;;

        check|check-rpmdb)
            COMPREPLY=( $( compgen -W 'dependencies duplicates all' \
                -- "$cur" ) )
            return 0
            ;;

        check-update|makecache|resolvedep)
            return 0
            ;;

        clean)
            [[ $prev == $cmd ]] && \
                COMPREPLY=( $( compgen -W 'expire-cache packages headers
                    metadata cache dbcache all' -- "$cur" ) )
            return 0
            ;;

        deplist)
            local IFS=$'\n'
            COMPREPLY=( $( compgen -f -o plusdirs -X '!*.[rs]pm' -- "$cur" ) )
            _yum_list all "$cur"
            return 0
            ;;

        distro-sync|distribution-synchronization)
            [[ $prev == $cmd ]] && \
                COMPREPLY=( $( compgen -W 'full different' -- "$cur" ) )
            _yum_list installed "$cur"
            return 0
            ;;

        downgrade|reinstall)
            if ! _yum_atgroups "$cur" ; then
                _yum_binrpmfiles "$cur"
                _yum_list installed "$cur"
            fi
            return 0
            ;;

        group*)
            if [[ ($cmd == groups || $cmd == group) && $prev == $cmd ]] ; then
                COMPREPLY=( $( compgen -W 'info install list remove summary' \
                    -- "$cur" ) )
            else
                _yum_helper groups list all "$cur"
            fi
            return 0
            ;;

        help)
            [[ $prev == $cmd ]] && \
                COMPREPLY=( $( compgen -W '${cmds[@]}' -- "$cur" ) )
            return 0
            ;;

        history)
            if [[ $prev == $cmd ]] ; then
                COMPREPLY=( $( compgen -W 'info list packages-list
                    packages-info summary addon-info redo undo rollback new
                    sync stats' -- "$cur" ) )
                return 0
            fi
            case $subcmd in
                undo|repeat|addon|addon-info|rollback)
                    if [[ $prev == $subcmd ]]; then
                        COMPREPLY=( $( compgen -W "last" -- "$cur" ) )
                        _yum_transactions
                    fi
                    ;;
                redo)
                    case $prev in
                        redo)
                            COMPREPLY=( $( compgen -W "force-reinstall
                                force-remove last" -- "$cur" ) )
                            _yum_transactions
                            ;;
                        reinstall|force-reinstall|remove|force-remove)
                            COMPREPLY=( $( compgen -W "last" -- "$cur" ) )
                            _yum_transactions
                            ;;
                    esac
                    ;;
                package-list|pkg|pkgs|pkg-list|pkgs-list|package|packages|\
                packages-list|pkg-info|pkgs-info|package-info|packages-info)
                    _yum_list available "$cur"
                    ;;
                info|list|summary)
                    if [[ $subcmd != info ]] ; then
                        COMPREPLY=( $( compgen -W "all" -- "$cur" ) )
                        [[ $cur != all ]] && _yum_list available "$cur"
                    else
                        _yum_list available "$cur"
                    fi
                    _yum_transactions
                    ;;
                sync|synchronize)
                    _yum_list installed "$cur"
                    ;;
            esac
            return 0
            ;;

        info)
            _yum_list all "$cur"
            return 0
            ;;

        install)
            if ! _yum_atgroups "$cur" ; then
                _yum_binrpmfiles "$cur"
                _yum_list available "$cur"
            fi
            return 0
            ;;

        install-na)
            _yum_list available "$cur"
            return 0
            ;;

        list)
            [[ $prev == $cmd ]] && \
                COMPREPLY=( $( compgen -W 'all available updates installed
                    extras obsoletes recent' -- "$cur" ) )
            return 0
            ;;

        load-transaction|load-ts)
            local IFS=$'\n'
            COMPREPLY=( $( compgen -f -o plusdirs -X '!*.yumtx' -- "$cur" ) )
            return 0
            ;;

        localinstall|localupdate)
            _yum_binrpmfiles "$cur"
            return 0
            ;;

        provides|whatprovides)
            local IFS=$'\n'
            COMPREPLY=( $( compgen -f -o plusdirs -- "$cur" ) )
            return 0
            ;;

        repolist)
            [[ $prev == $cmd ]] && \
                COMPREPLY=( $( compgen -W 'all enabled disabled' -- "$cur" ) )
            return 0
            ;;

        search)
            [[ $prev == $cmd ]] && COMPREPLY=( $( compgen -W 'all' -- "$cur" ) )
            return 0
            ;;

        shell)
            if [[ $prev == $cmd ]]; then
                local IFS=$'\n'
                COMPREPLY=( $( compgen -f -o plusdirs -- "$cur" ) )
            fi
            return 0
            ;;

        update|upgrade)
            if ! _yum_atgroups "$cur" ; then
                _yum_binrpmfiles "$cur"
                _yum_list updates "$cur"
            fi
            return 0
            ;;
        version)
            [[ $prev == $cmd ]] && \
                COMPREPLY=( $( compgen -W 'all installed available nogroups
                    grouplist groupinfo' -- "$cur" ) )
            return 0
            ;;
    esac

    local split=false
    declare -F _split_longopt &>/dev/null && _split_longopt && split=true

    _yum_complete_baseopts "$cur" "$prev" && return 0

    $split && return 0

    if [[ $cur == -* ]] ; then
        COMPREPLY=( $( compgen -W '$( _yum_baseopts )' -- "$cur" ) )
        return 0
    fi
    COMPREPLY=( $( compgen -W '${cmds[@]}' -- "$cur" ) )
} &&
complete -F _yum -o filenames yum yummain.py

# Local variables:
# mode: shell-script
# sh-basic-offset: 4
# sh-indent-comment: t
# indent-tabs-mode: nil
# End:
# ex: ts=4 sw=4 et filetype=sh
