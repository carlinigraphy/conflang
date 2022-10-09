#!/bin/bash

function isfile-test {
   [[ -d "$DATA" ]]
}

function isfile-directive {
   mkfile -p "$DATA" || raise validation_error 'isfile'
}
