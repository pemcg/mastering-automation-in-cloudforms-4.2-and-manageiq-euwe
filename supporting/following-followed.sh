#!/bin/bash
# Small snippet of code to indent the automation.log file of CloudForms, so
# that it's easier to follow the flow of followed relationships and invoked
# methods.
# The snippet doesn't handle well multiple concurrent requests, and you should
# make sure you don't start the script in the middle of a request or the
# identation will be wrong.
# Author: Eric Lavarde

cat service_provision_log_lines | \
    awk 'BEGIN {indent=0;}
        { output = 0; } # set this to 0 to see only branching, to 1 to see everything
        /Followed  Relationship/ || /Method exited/ {indent--; if (indent < 0) indent=0; output = 1}
        /Following Relationship/ || /Invoking \[.*\] method/ {output = 1}
        /Instantiating/ { # probably a new workflow
            print "";
            for(i=0; i<80; i++) {printf "%s","-"}; print "";
            print "";
            output = 1;
        }
        {
            if (output == 0) next;
            for(i=0; i<indent; i++) {printf "%s","  "};
            if (output) print;
        }
        /Following Relationship/ || /Invoking \[.*\] method/ {indent++}
        /Invoking \[builtin\] method/ {indent--} # builtin methods do not come back so we do not indent them
    ' # End of AWK script
