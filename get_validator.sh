#!/usr/bin/env sh

#wget https://github.com/hapifhir/org.hl7.fhir.core/releases/download/5.6.54/validator_cli.jar --no-check-certificate
wget https://github.com/hapifhir/org.hl7.fhir.core/releases/download/5.6.54/validator_cli.jar --no-check-certificate
mv validator_cli.jar lib/validator_cli.jar
