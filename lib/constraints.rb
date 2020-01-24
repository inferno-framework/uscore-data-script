require 'date'

module DataScript
  class Constraints

    CONSTRAINTS = {
      'one_male' => lambda {|results| results.any? {|bundle| gender(bundle) == 'male'}},
      'one_female' => lambda {|results| results.any? {|bundle| gender(bundle) == 'female'}},
      'one_child' => lambda {|results| results.any? {|bundle| age(bundle) < 18 }},
      'child_has_immunizations' => lambda {|results| results.any? {|bundle| (age(bundle) < 18) && has(bundle, FHIR::Immunization) }},
      'child_does_not_smoke' => lambda {|results| results.any? {|bundle| (age(bundle) < 18) && !smoker(bundle) }},
      'one_adult' => lambda {|results| results.any? {|bundle| age = age(bundle); age >= 18 && age <= 65  }},
      'one_elder' => lambda {|results| results.any? {|bundle| age(bundle) > 65 }},
      'elder_has_device' => lambda {|results| results.any? {|bundle| (age(bundle) > 65) && has(bundle, FHIR::Device) }},
      'elder_is_alive' => lambda {|results| results.any? {|bundle| (age(bundle) > 65) && alive(bundle) }},
      'one_white' => lambda {|results| results.any? {|bundle| race(bundle) == 'White'}},
      'one_black' => lambda {|results| results.any? {|bundle| race(bundle) == 'Black or African American'}},
      'one_hispanic' => lambda {|results| results.any? {|bundle| ethnicity(bundle) == 'Hispanic or Latino'}},
      'one_smoker' => lambda {|results| results.any? {|bundle| smoker(bundle) }}
    }

    CONSTRAINTS_MRBURNS = {
      'has_allergy' => lambda {|results| results.any? {|bundle| has(bundle, FHIR::AllergyIntolerance) }},
      'has_pulse_ox' => lambda {|results| results.any? {|bundle| has_pulse_ox(bundle) }},
    }

    CONSTRAINTS_MRBURNS_DOES_NOT_NEED = [
      'one_female',
      'one_child',
      'child_has_immunizations',
      'child_does_not_smoke',
      'one_adult',
      'elder_is_alive',
      'one_white',
      'one_black',
      'one_hispanic',
      'one_smoker',
    ]

    REQUIRED_PROFILES = [
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-allergyintolerance',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-careplan',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-careteam',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-condition',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-diagnosticreport-lab',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-diagnosticreport-note',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-documentreference',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-encounter',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-goal',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-immunization',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-implantable-device',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-observation-lab',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-location',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-medication',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-medicationrequest',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-organization',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-patient',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-practitioner',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-practitionerrole',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-procedure',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-provenance',
      'http://hl7.org/fhir/us/core/StructureDefinition/pediatric-bmi-for-age',
      'http://hl7.org/fhir/us/core/StructureDefinition/pediatric-weight-for-height',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-smokingstatus',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-pulse-oximetry',
      'http://hl7.org/fhir/StructureDefinition/vitalspanel',
      'http://hl7.org/fhir/StructureDefinition/resprate',
      'http://hl7.org/fhir/StructureDefinition/heartrate',
      'http://hl7.org/fhir/StructureDefinition/bodytemp',
      'http://hl7.org/fhir/StructureDefinition/bodyheight',
      'http://hl7.org/fhir/StructureDefinition/headcircum',
      'http://hl7.org/fhir/StructureDefinition/bodyweight',
      'http://hl7.org/fhir/StructureDefinition/bmi',
      'http://hl7.org/fhir/StructureDefinition/bp'
    ]

    attr_accessor :violations

    def initialize
      @violations = []
    end

    def satisfied?(results, keys = CONSTRAINTS.keys)
      @violations.clear
      constraints = CONSTRAINTS.keep_if {|key, test| keys.include?(key)}
      constraints.each do |key, test|
        test_result = test.call(results)
        unless test_result
          @violations << key
        end
      end
      @violations.empty?
    end

    def profiles_present(results)
      present = results.map {|b| b.entry.map {|e| e.resource&.meta&.profile }}.flatten.uniq
      present.delete(nil)
      present
    end

    def self.patient(bundle)
      bundle.entry.each do |entry|
        return entry.resource if entry.resource.is_a?(FHIR::Patient)
      end
      nil
    end

    def self.gender(bundle)
      self.patient(bundle)&.gender
    end

    def self.age(bundle)
      birth_date = self.patient(bundle)&.birthDate
      date = Date.parse(birth_date)
      age = Date.today.year - date.year
      age -= 1 if Date.today < date.next_year(age)
      age
    end

    def self.alive(bundle)
      p = self.patient(bundle)
      ((p&.deceasedBoolean.nil? || p&.deceasedBoolean == false) && p&.deceasedDateTime.nil?)
    end

    def self.race(bundle)
      self.patient(bundle)&.us_core_race&.ombCategory&.display rescue nil
    end

    def self.ethnicity(bundle)
      self.patient(bundle)&.us_core_ethnicity&.ombCategory&.display rescue nil
    end

    def self.smoker(bundle)
      entries = bundle.entry.select {|entry| entry.resource.is_a?(FHIR::Observation)}
      observations = entries.map {|entry| entry.resource}
      smoking_statuses = observations.select {|observation| observation.code.text == 'Tobacco smoking status NHIS'}
      smoking_statuses.map {|status| status.value.text}.include? 'Current every day smoker'
    end

    def self.has(bundle, fhir_class)
      bundle.entry.any? {|entry| entry.resource.is_a?(fhir_class)}
    end

    def self.has_pulse_ox(bundle)
      bundle.entry.each do |entry|
        return true if entry.resource&.meta&.profile&.include? 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-pulse-oximetry'
      end
      false
    end
  end
end