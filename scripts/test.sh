#!/bin/bash

function run_test {
    printf "πππRunning Tests NOW\n"
    af-cli package test --coverage --dev -i 1000000

    if [ $? -ne 0 ]; then
        printf "βββ Oops, not all tests passed βββ"
    fi
    printf "βββ Tests Passed\n"
}

function check_coverage {
    printf "\nπππChecking Code Coverage\n"


    COVERAGE=$(af-cli package coverage summary --dev)

    echo "${COVERAGE}"

    SAVEIFS=$IFS   # Save current IFS (Internal Field Separator)
    IFS=$'\n'      # Change IFS to newline char
    COVERAGE=($COVERAGE) # split the `COVERAGE` string into an array by the same name
    IFS=$SAVEIFS   # Restore original IFS

    ERRORMODULE=0


    PASS='>>> % Module coverage: 100.00'
    MATCH='>>> % Module coverage:'

    for (( i=0; i<${#COVERAGE[@]}; i++ ))
    do
      if [[ ${COVERAGE[$i]} =~ ^"$MATCH".*  ]]; then
        if ! [[ ${COVERAGE[$i]} =~ ^"$PASS".* ]]; then
          ERRORMODULE=$(( ERRORMODULE + 1 ))
        fi
      fi
    done
    if [[ $ERRORMODULE != 0 ]]; then
      echo "βββ Oops, ${ERRORMODULE} modules not passed. βββ"
      exit 1;
    fi
    printf "βββ Test Coverage Passed\n"
}

run_test
check_coverage
