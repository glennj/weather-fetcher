#! tclsh
#
# $Id: weather.tcl 25 2008-11-26 20:02:48Z glennj $
#
# grab the Environment Canada RSS feed for Ottawa and
# extract the most recent conditions and warnings.

package require Tcl 8.5

# http://www.tdom.org/ 
package require tdom

# http://tcllib.sf.net
package require textutil; namespace import textutil::adjust textutil::indent
package require cmdline

set auto_path [linsert $auto_path 0 [file join $env(HOME) tcl lib]]
package require httplib

################################################################################
set options { {v "show verbose debugging"} {terse "briefer output"}}
set usage ": [file rootname [info script]] \[-v\] \[-terse\]"
if {[catch {array set params [::cmdline::getoptions argv $options $usage]} out] != 0} {
    puts $out
    exit
}
set debug $params(v)
set terse $params(terse)
set textwidth 56

set url http://www.weatheroffice.gc.ca/rss/city/on-118_e.xml

set categories [dict create {*}{
    current  "Current Conditions"
    warnings "Warnings and Watches"
    forecast "Weather Forecasts"
}]

proc main {} {
    httplib::setProxy -debug $::debug

    if {[catch {httplib::getHtml $::url -timeout 5 -debug $::debug} xml] != 0} {
        switch -glob -- $xml {
            *timeout* {
                puts "timeout fetching $::url"
                exit
            }
            default {
                error $xml
            }
        }
    }
    debug $xml

    set weather [parseXML $xml]
    dict_parray weather
    display $weather
}

proc parseXML {xml} {
    set doc [dom parse $xml]
    set weather [dict create]
    foreach item [$doc getElementsByTagName "item"] {
        set item_info [dict create]
        foreach child [$item childNodes] {
            switch -exact -- [set tag [string tolower [$child nodeName]]] {
                category -
                description -
                link -
                title {
                    dict set item_info $tag [$child text]
                    debug "... [dict get $item_info]"
                }
            }
        }
        debug "--- [dict get $item_info]"
        dict lappend weather [dict get $item_info category] $item_info 
    }
    $doc delete
    debug ">>> [dict get $weather]"
    return $weather
}

proc display {weather} {
    global terse

    set time_fmt "%Y-%m-%d %l:%M %p"
    if { ! $terse} {
        puts "At: [clock format [clock seconds] -format $time_fmt]"
        puts ""
    }

    # current conditions
    set d [lindex [dict get $weather [dict get $::categories current]] 0]
    dict_parray d

    if { ! $terse} {puts [stripDegree [stripHtml [dict get $d title]]]}

    set out_fmt "YOW, $time_fmt"
    set in_fmt "Ottawa Macdonald-Cartier Int'l Airport %I:%M %p %z %A %d %B %Y"
    regsub -line \
        {(Observed at: )(.*)$} \
        [stripDegree [stripHtml [dict get $d description]]] \
        {\1[clock format [clock scan {\2} -format $in_fmt] -format $out_fmt]} \
        desc
    foreach line [split [string trimright [subst $desc]] \n] {
        if {$terse} {
            switch -regexp -- $line {
                Condition -
                Temperature -
                Wind {puts $line}
            }
            continue
        } else {
            puts [format_paragraph $line]
        }
    }

    puts ""

    # warnings
    if { ! $terse} {
        set d [lindex [dict get $weather [dict get $::categories warnings]] 0]
        puts [dict get $d category]
        set warn [lindex [split [stripHtml [dict get $d title]] ,] 0]
        puts [format_paragraph $warn]
        if {! [string match "No watches or warnings*" $warn]} { 
            puts [format_paragraph [stripHtml [dict get $d description]]]
            puts [format_paragraph [stripHtml [dict get $d link]]]
        }

        puts ""
    }

    # forecast
    puts [set forecast [dict get $::categories forecast]]
    foreach d [dict get $weather $forecast] {
        set title [stripHtml [dict get $d title]]
        if {$terse} {
            set X $title
            if {[incr terse_count] > 4} break
        } else {
            set X [string range $title 0 [string first : $title]]
            set desc [stripHtml [dict get $d description]]
            append X " " [regsub {^(.+) Forecast issued.*} $desc {\1}]
        }
        regsub -all {\mplus } $X {} X
        regsub -all {\mminus } $X {-} X
        regsub -all { percent} $X {%} X
        puts [format_paragraph $X]
    }
}

proc stripHtml {text} {
    #regsub -all {<.*?>} $text {} new
    # ref: http://faq.perl.org/perlfaq9.html#How_do_I_remove_HTML 
    return [regsub -all {<(?:[^>'"]*?|(['"]).*?\1)*>} $text {}]
}

proc stripDegree {str} {
    # glennj 20081118 -- leave it in
    return $str
    ###########################################################################
    regsub -all -line {.C\s*$} $str { C} X
    return $X
}

proc format_paragraph {str} {
    # first, format the paragraph for the textwidth,
    # then create a hanging indent,
    # then indent the whole new paragraph again
    return [indent [indent [adjust $str -length $::textwidth] "   " 1] "   "]
}

proc debug str {if {$::debug} {puts $str}}

proc dict_parray {dictname} {
    upvar 1 $dictname dict
    if {$::debug} {
        puts "==================="
        array set $dictname [dict get $dict]
        parray $dictname
        puts "==================="
    }
}

main
