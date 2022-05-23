#!/bin/zsh

af-cli sandbox clean
af-cli package build
af-cli package test
af-cli sandbox publish
# af-cli sandbox run sources/tests/test_register.move --signers 0xAE
# af-cli sandbox run sources/tests/test_mint.move --signers 0xAE
