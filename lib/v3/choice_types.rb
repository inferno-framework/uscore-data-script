module DataScript
  # Version specific constants go here, other methods go in ../choice_type_creator.rb
  class ChoiceTypeCreator
    MUST_SUPPORT_CHOICE_TYPES = {
      FHIR::DiagnosticReport =>
      {
        prefix: 'effective',
        suffixes: %w[DateTime Period],
        profiles: [
          'http://hl7.org/fhir/us/core/StructureDefinition/us-core-diagnosticreport-note',
          'http://hl7.org/fhir/us/core/StructureDefinition/us-core-diagnosticreport-lab'
        ]
      },
      FHIR::Immunization =>
      {
        prefix: 'occurrence',
        suffixes: %w[DateTime String],
        profiles: [
          'http://hl7.org/fhir/us/core/StructureDefinition/us-core-immunization'
        ]
      },
      FHIR::Observation =>
      {
        prefix: 'effective',
        suffixes: %w[DateTime Period],
        profiles: [
          'http://hl7.org/fhir/StructureDefinition/resprate',
          'http://hl7.org/fhir/StructureDefinition/heartrate',
          'http://hl7.org/fhir/StructureDefinition/bodyweight',
          'http://hl7.org/fhir/StructureDefinition/bp',
          'http://hl7.org/fhir/us/core/StructureDefinition/us-core-smokingstatus',
          'http://hl7.org/fhir/us/core/StructureDefinition/pediatric-weight-for-height',
          'http://hl7.org/fhir/us/core/StructureDefinition/us-core-observation-lab',
          'http://hl7.org/fhir/us/core/StructureDefinition/pediatric-bmi-for-age',
          'http://hl7.org/fhir/us/core/StructureDefinition/us-core-pulse-oximetry',
          'http://hl7.org/fhir/us/core/StructureDefinition/head-occipital-frontal-circumference-percentile',
          'http://hl7.org/fhir/StructureDefinition/bodyheight',
          'http://hl7.org/fhir/StructureDefinition/bodytemp'
        ]
      },
      FHIR::Procedure =>
      {
        prefix: 'performed',
        suffixes: %w[DateTime Period],
        profiles: [
          'http://hl7.org/fhir/us/core/StructureDefinition/us-core-procedure'
        ]
      }
    }.freeze
  end
end