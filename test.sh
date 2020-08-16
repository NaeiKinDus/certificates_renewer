#!/usr/bin/env bash

source ./.env.test

./renew_certs.sh -vd -e .env.test run "${TEST_DOMAIN_1}" "${TEST_DOMAIN_2}"
./renew_certs.sh -vd -e .env.test renew "${TEST_DOMAIN_1}" "${TEST_DOMAIN_2}"
