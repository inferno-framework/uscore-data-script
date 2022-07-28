module DataScript
  class ValidationMessageChecks
    def self.check(line)
      return line if line.nil?

          # the tooling can't expand this valueset for some reason...
      if (line.include?('The Coding provided (urn:oid:2.16.840.1.113883.6.238#1002-5) is not in the value set http://hl7.org/fhir/us/core/ValueSet/omb-race-category')  ||
          line.include?('The Coding provided (urn:oid:2.16.840.1.113883.6.238#2028-9) is not in the value set http://hl7.org/fhir/us/core/ValueSet/omb-race-category')  ||
          line.include?('The Coding provided (urn:oid:2.16.840.1.113883.6.238#2054-5) is not in the value set http://hl7.org/fhir/us/core/ValueSet/omb-race-category')  ||
          line.include?('The Coding provided (urn:oid:2.16.840.1.113883.6.238#2076-8) is not in the value set http://hl7.org/fhir/us/core/ValueSet/omb-race-category')  ||
          line.include?('The Coding provided (urn:oid:2.16.840.1.113883.6.238#2106-3) is not in the value set http://hl7.org/fhir/us/core/ValueSet/omb-race-category')  ||
          line.include?('The Coding provided (urn:oid:2.16.840.1.113883.6.238#2131-1) is not in the value set http://hl7.org/fhir/us/core/ValueSet/omb-race-category')  ||
          line.include?('The Coding provided (urn:oid:2.16.840.1.113883.6.238#ASKU) is not in the value set http://hl7.org/fhir/us/core/ValueSet/omb-race-category')  ||
          line.include?('The Coding provided (urn:oid:2.16.840.1.113883.6.238#UNK) is not in the value set http://hl7.org/fhir/us/core/ValueSet/omb-race-category')  ||
          # the tooling can't expand this valueset for some reason...
          line.include?('The Coding provided (urn:oid:2.16.840.1.113883.6.238#2135-2) is not in the value set http://hl7.org/fhir/us/core/ValueSet/omb-ethnicity-category')  ||
          line.include?('The Coding provided (urn:oid:2.16.840.1.113883.6.238#2186-5) is not in the value set http://hl7.org/fhir/us/core/ValueSet/omb-ethnicity-category')  ||
          line.include?('The Coding provided (urn:oid:2.16.840.1.113883.6.238#ASKU) is not in the value set http://hl7.org/fhir/us/core/ValueSet/omb-ethnicity-category')  ||
          line.include?('The Coding provided (urn:oid:2.16.840.1.113883.6.238#UNK) is not in the value set http://hl7.org/fhir/us/core/ValueSet/omb-ethnicity-category')  ||
          # the tooling can't expand this valueset for some reason...
          line.include?("The value provided (\'F\') is not in the value set \'Birth Sex\' (http://hl7.org/fhir/us/core/ValueSet/birthsex")  ||
          line.include?("The value provided (\'M\') is not in the value set \'Birth Sex\' (http://hl7.org/fhir/us/core/ValueSet/birthsex")  ||
          line.include?("The value provided (\'OTH\') is not in the value set \'Birth Sex\' (http://hl7.org/fhir/us/core/ValueSet/birthsex")  ||
          line.include?("The value provided (\'UNK\') is not in the value set \'Birth Sex\' (http://hl7.org/fhir/us/core/ValueSet/birthsex")  ||
          line.include?("The value provided (\'UNK\') is not in the value set \'Birth Sex\' (http://hl7.org/fhir/us/core/ValueSet/birthsex")  ||
          # the tooling can't expand this valueset for some reason...
          line.include?('The filter "concept = 768734005" from the value set http://cts.nlm.nih.gov/fhir/ValueSet/2.16.840.1.113762.1.4.1099.27 was not understood in the context of http://snomed.info/sct')  ||
          # the tooling can't tell that references to our patient are to a us-core-patient
          (line.include?('Unable to find a match for profile') && line.include?('http://hl7.org/fhir/us/core/StructureDefinition/us-core-patient')) ||
          # the invariant is wrong or the tooling can't figure it out
          (line.include?('resource.ofType(DiagnosticReport)') && line.include?('us-core-8')) ||
          # the invariant is wrong or the tooling can't figure it out
          (line.include?('resource.ofType(Provenance)') && line.include?('provenance-1')))

        return "  IGNORE#{line.sub('Error','')}"
      end

      line
    end
  end
end
