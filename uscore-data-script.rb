require 'pry'
require 'fhir_models'
require 'fileutils'
require './lib/time.rb'
require './lib/bulk_data_converter.rb'
require './lib/filter.rb'

RAND_SEED = 3

def error(message)
  puts "\e[31m#{message}\e[0m"
end

start = Time.now.to_i

if ARGV && ARGV.length >= 1
  if ARGV.include?('v3')
    puts 'Using US Core version 3...'
    VERSION = 3
    require './lib/v3/constraints.rb'
    require './lib/v3/modifications.rb'
    require './lib/v3/choice_types.rb'
  elsif ARGV.include?('v4')
    puts 'Using US Core version 4...'
    VERSION = 4
    require './lib/v4/constraints.rb'
    require './lib/v4/modifications.rb'
    require './lib/v4/choice_types.rb'
  elsif ARGV.include?('v5')
    puts 'Using US Core version 5...'
    VERSION = 5
    require './lib/v5/constraints.rb'
    require './lib/v5/modifications.rb'
    require './lib/v5/choice_types.rb'
    require './lib/v5/validation_message_checks.rb'
  else
    puts 'Using US Core version 4...'
    VERSION = 4
    require './lib/v4/constraints.rb'
    require './lib/v4/modifications.rb'
    require './lib/v4/choice_types.rb'
  end
else
  puts 'Using US Core version 4...'
  VERSION = 4
  require './lib/v4/constraints.rb'
  require './lib/v4/modifications.rb'
  require './lib/v4/choice_types.rb'
end

if ARGV && ARGV.length >= 1 && ARGV.include?('mrburns')
  puts 'Generating Mr. Burns...'
  MRBURNS=true
  DataScript::Constraints::CONSTRAINTS_MRBURNS_DOES_NOT_NEED.each do |key|
    DataScript::Constraints::CONSTRAINTS.delete(key)
  end
  DataScript::Constraints::CONSTRAINTS.merge!(DataScript::Constraints::CONSTRAINTS_MRBURNS)
  DataScript::Constraints::REQUIRED_PROFILES.delete('http://hl7.org/fhir/us/core/StructureDefinition/us-core-medication')
else
  MRBURNS = false
end

def validate(filename, validation_file)
  uscore_ver = '3.1.1'
  uscore_ver = '4.0.0' if VERSION == 4
  uscore_ver = '5.0.1' if VERSION == 5
  system( "java -jar lib/validator_cli.jar #{filename} -sct us -version 4.0.1 -ig hl7.fhir.us.core##{uscore_ver} > #{validation_file}" )

  if VERSION == 5
    logfile = File.open(validation_file, 'r:UTF-8')
    filepath = validation_file.split(File::Separator)
    filepath[filepath.length-1] = "_#{filepath.last}"
    modifiedFilename = filepath.join(File::Separator)
    modifiedLogFile = File.open(modifiedFilename, 'w:UTF-8')

    logfile.each do |line|
      if line.start_with?('  Error @ Bundle.entry')
        new_line = DataScript::ValidationMessageChecks.check(line)
        modifiedLogFile.write(new_line) unless new_line.nil?
      else
        modifiedLogFile.write(line)
      end
    end

    logfile.close
    modifiedLogFile.close
  end
end

puts 'Generating Synthetic Patients with Synthea...'
output = 'output'
output_raw = 'output/raw'
output_raw_fhir = 'output/raw/fhir'
FileUtils.rm Dir.glob("./#{output}/*.log")
Dir.mkdir(output) unless File.exists?(output)
Dir.mkdir(output_raw) unless File.exists?(output_raw)
Dir.mkdir(output_raw_fhir) unless File.exists?(output_raw_fhir)
FileUtils.rm Dir.glob("./#{output_raw_fhir}/*.json")

# Manually list out the classpath, because it needs to be loaded in a specific order...
if VERSION == 3
  CLASSPATH='lib/synthea_uscore_v3/synthea.jar:lib/synthea_uscore_v3/SimulationCoreLibrary_v1.5_slim.jar:lib/synthea_uscore_v3/hapi-fhir-structures-dstu3-4.1.0.jar:lib/synthea_uscore_v3/hapi-fhir-structures-dstu2-4.1.0.jar:lib/synthea_uscore_v3/hapi-fhir-structures-r4-4.1.0.jar:lib/synthea_uscore_v3/org.hl7.fhir.dstu3-4.1.0.jar:lib/synthea_uscore_v3/org.hl7.fhir.r4-4.1.0.jar:lib/synthea_uscore_v3/org.hl7.fhir.utilities-4.1.0.jar:lib/synthea_uscore_v3/hapi-fhir-base-4.1.0.jar:lib/synthea_uscore_v3/gson-2.8.5.jar:lib/synthea_uscore_v3/json-path-2.4.0.jar:lib/synthea_uscore_v3/freemarker-2.3.26-incubating.jar:lib/synthea_uscore_v3/h2-1.4.196.jar:lib/synthea_uscore_v3/guava-28.0-jre.jar:lib/synthea_uscore_v3/graphviz-java-0.2.2.jar:lib/synthea_uscore_v3/commons-csv-1.5.jar:lib/synthea_uscore_v3/jackson-dataformat-csv-2.8.8.jar:lib/synthea_uscore_v3/snakeyaml-1.25.jar:lib/synthea_uscore_v3/commons-math3-3.6.1.jar:lib/synthea_uscore_v3/commons-text-1.7.jar:lib/synthea_uscore_v3/cql-engine-1.3.10-SNAPSHOT.jar:lib/synthea_uscore_v3/cql-to-elm-1.3.17.jar:lib/synthea_uscore_v3/cql-1.3.17.jar:lib/synthea_uscore_v3/elm-1.3.17.jar:lib/synthea_uscore_v3/model-1.3.17.jar:lib/synthea_uscore_v3/jaxb-runtime-2.3.0.jar:lib/synthea_uscore_v3/jaxb-core-2.3.0.jar:lib/synthea_uscore_v3/jaxb-api-2.3.0.jar:lib/synthea_uscore_v3/activation-1.1.1.jar:lib/synthea_uscore_v3/quick-1.3.17.jar:lib/synthea_uscore_v3/qdm-1.3.17.jar:lib/synthea_uscore_v3/jaxb2-basics-0.9.4.jar:lib/synthea_uscore_v3/jaxb2-basics-tools-0.9.4.jar:lib/synthea_uscore_v3/jcl-over-slf4j-1.7.28.jar:lib/synthea_uscore_v3/jul-to-slf4j-1.7.25.jar:lib/synthea_uscore_v3/slf4j-log4j12-1.7.25.jar:lib/synthea_uscore_v3/jsbml-1.4.jar:lib/synthea_uscore_v3/jsbml-arrays-1.4.jar:lib/synthea_uscore_v3/jsbml-comp-1.4.jar:lib/synthea_uscore_v3/jsbml-distrib-1.3.1.jar:lib/synthea_uscore_v3/jsbml-dyn-1.4.jar:lib/synthea_uscore_v3/jsbml-fbc-1.4.jar:lib/synthea_uscore_v3/jsbml-groups-1.4.jar:lib/synthea_uscore_v3/jsbml-render-1.4.jar:lib/synthea_uscore_v3/jsbml-layout-1.4.jar:lib/synthea_uscore_v3/jsbml-multi-1.4.jar:lib/synthea_uscore_v3/jsbml-qual-1.4.jar:lib/synthea_uscore_v3/jsbml-req-1.4.jar:lib/synthea_uscore_v3/jsbml-spatial-1.4.jar:lib/synthea_uscore_v3/jsbml-tidy-1.4.jar:lib/synthea_uscore_v3/jsbml-core-1.4.jar:lib/synthea_uscore_v3/biojava-ontology-4.0.0.jar:lib/synthea_uscore_v3/log4j-slf4j-impl-2.1.jar:lib/synthea_uscore_v3/slf4j-api-1.7.28.jar:lib/synthea_uscore_v3/commons-math-2.2.jar:lib/synthea_uscore_v3/jfreechart-1.5.0.jar:lib/synthea_uscore_v3/json-smart-2.3.jar:lib/synthea_uscore_v3/commons-lang3-3.9.jar:lib/synthea_uscore_v3/commons-codec-1.12.jar:lib/synthea_uscore_v3/batik-codec-1.9.jar:lib/synthea_uscore_v3/batik-rasterizer-1.9.jar:lib/synthea_uscore_v3/batik-svgrasterizer-1.9.jar:lib/synthea_uscore_v3/batik-transcoder-1.9.jar:lib/synthea_uscore_v3/batik-bridge-1.9.jar:lib/synthea_uscore_v3/batik-script-1.9.jar:lib/synthea_uscore_v3/batik-anim-1.9.jar:lib/synthea_uscore_v3/batik-svg-dom-1.9.jar:lib/synthea_uscore_v3/batik-dom-1.9.jar:lib/synthea_uscore_v3/batik-css-1.9.jar:lib/synthea_uscore_v3/xmlgraphics-commons-2.2.jar:lib/synthea_uscore_v3/commons-io-2.6.jar:lib/synthea_uscore_v3/ucum-1.0.2.jar:lib/synthea_uscore_v3/jsr305-3.0.2.jar:lib/synthea_uscore_v3/j2v8_macosx_x86_64-4.6.0.jar:lib/synthea_uscore_v3/j2v8_linux_x86_64-4.6.0.jar:lib/synthea_uscore_v3/j2v8_win32_x86_64-4.6.0.jar:lib/synthea_uscore_v3/j2v8_win32_x86-4.6.0.jar:lib/synthea_uscore_v3/commons-exec-1.3.jar:lib/synthea_uscore_v3/jackson-databind-2.10.1.jar:lib/synthea_uscore_v3/jackson-core-2.10.1.jar:lib/synthea_uscore_v3/jackson-annotations-2.10.1.jar:lib/synthea_uscore_v3/jaxb2-fluent-api-3.0.jar:lib/synthea_uscore_v3/hamcrest-all-1.3.jar:lib/synthea_uscore_v3/hamcrest-json-0.2.jar:lib/synthea_uscore_v3/jaxb-impl-2.3.0.1.jar:lib/synthea_uscore_v3/jaxb-core-2.3.0.1.jar:lib/synthea_uscore_v3/javax.activation-1.2.0.jar:lib/synthea_uscore_v3/eclipselink-2.6.0.jar:lib/synthea_uscore_v3/validation-api-1.1.0.Final.jar:lib/synthea_uscore_v3/antlr4-4.5.jar:lib/synthea_uscore_v3/jopt-simple-4.7.jar:lib/synthea_uscore_v3/stax-ex-1.7.8.jar:lib/synthea_uscore_v3/FastInfoset-1.2.13.jar:lib/synthea_uscore_v3/accessors-smart-1.2.jar:lib/synthea_uscore_v3/failureaccess-1.0.1.jar:lib/synthea_uscore_v3/listenablefuture-9999.0-empty-to-avoid-conflict-with-guava.jar:lib/synthea_uscore_v3/checker-qual-2.8.1.jar:lib/synthea_uscore_v3/error_prone_annotations-2.3.2.jar:lib/synthea_uscore_v3/j2objc-annotations-1.3.jar:lib/synthea_uscore_v3/animal-sniffer-annotations-1.17.jar:lib/synthea_uscore_v3/xpp3-1.1.4c.jar:lib/synthea_uscore_v3/xpp3_xpath-1.1.4c.jar:lib/synthea_uscore_v3/json-simple-1.1.1.jar:lib/synthea_uscore_v3/junit-4.12.jar:lib/synthea_uscore_v3/batik-parser-1.9.jar:lib/synthea_uscore_v3/batik-gvt-1.9.jar:lib/synthea_uscore_v3/batik-svggen-1.9.jar:lib/synthea_uscore_v3/batik-awt-util-1.9.jar:lib/synthea_uscore_v3/batik-xml-1.9.jar:lib/synthea_uscore_v3/batik-util-1.9.jar:lib/synthea_uscore_v3/xalan-2.7.2.jar:lib/synthea_uscore_v3/serializer-2.7.2.jar:lib/synthea_uscore_v3/xml-apis-1.3.04.jar:lib/synthea_uscore_v3/jaxb2-basics-runtime-0.9.4.jar:lib/synthea_uscore_v3/javaparser-1.0.11.jar:lib/synthea_uscore_v3/jsonassert-1.1.1.jar:lib/synthea_uscore_v3/hamcrest-core-1.3.jar:lib/synthea_uscore_v3/log4j-1.2.17.jar:lib/synthea_uscore_v3/javax.persistence-2.1.0.jar:lib/synthea_uscore_v3/commonj.sdo-2.1.1.jar:lib/synthea_uscore_v3/javax.json-1.0.4.jar:lib/synthea_uscore_v3/antlr4-runtime-4.5.jar:lib/synthea_uscore_v3/ST4-4.0.8.jar:lib/synthea_uscore_v3/antlr-runtime-3.5.2.jar:lib/synthea_uscore_v3/txw2-2.3.0.jar:lib/synthea_uscore_v3/istack-commons-runtime-3.0.5.jar:lib/synthea_uscore_v3/log4j-1.2-api-2.3.jar:lib/synthea_uscore_v3/log4j-core-2.3.jar:lib/synthea_uscore_v3/woodstox-core-5.0.1.jar:lib/synthea_uscore_v3/jigsaw-2.2.6.jar:lib/synthea_uscore_v3/xstream-1.3.1.jar:lib/synthea_uscore_v3/staxmate-2.3.0.jar:lib/synthea_uscore_v3/jtidy-r938.jar:lib/synthea_uscore_v3/asm-5.0.4.jar:lib/synthea_uscore_v3/batik-ext-1.9.jar:lib/synthea_uscore_v3/xml-apis-ext-1.3.04.jar:lib/synthea_uscore_v3/batik-constants-1.9.jar:lib/synthea_uscore_v3/batik-i18n-1.9.jar:lib/synthea_uscore_v3/commons-beanutils-1.9.2.jar:lib/synthea_uscore_v3/json-20090211.jar:lib/synthea_uscore_v3/commons-collections-3.2.1.jar:lib/synthea_uscore_v3/org.abego.treelayout.core-1.0.1.jar:lib/synthea_uscore_v3/log4j-api-2.3.jar:lib/synthea_uscore_v3/stax2-api-3.1.4.jar:lib/synthea_uscore_v3/xpp3_min-1.1.4c.jar:lib/synthea_uscore_v3/commons-logging-1.0.4.jar'
  CONFIG='--exporter.fhir.use_us_core_ig=true --exporter.baseDirectory=./output/raw --exporter.hospital.fhir.export=false --exporter.practitioner.fhir.export=false --exporter.groups.fhir.export=true'
elsif VERSION >= 4
  CLASSPATH='lib/synthea_uscore_v4/synthea.jar:lib/synthea_uscore_v4/SimulationCoreLibrary_v1.5_slim.jar:lib/synthea_uscore_v4/gson-2.8.7.jar:lib/synthea_uscore_v4/json-path-2.4.0.jar:lib/synthea_uscore_v4/hapi-fhir-structures-dstu3-5.7.0.jar:lib/synthea_uscore_v4/hapi-fhir-structures-dstu2-5.7.0.jar:lib/synthea_uscore_v4/hapi-fhir-structures-r4-5.7.0.jar:lib/synthea_uscore_v4/hapi-fhir-client-5.7.0.jar:lib/synthea_uscore_v4/org.hl7.fhir.dstu3-5.6.27.jar:lib/synthea_uscore_v4/org.hl7.fhir.r4-5.6.27.jar:lib/synthea_uscore_v4/org.hl7.fhir.utilities-5.6.27.jar:lib/synthea_uscore_v4/hapi-fhir-base-5.7.0.jar:lib/synthea_uscore_v4/freemarker-2.3.26-incubating.jar:lib/synthea_uscore_v4/guava-31.0.1-jre.jar:lib/synthea_uscore_v4/graphviz-java-0.2.4.jar:lib/synthea_uscore_v4/commons-csv-1.5.jar:lib/synthea_uscore_v4/jackson-datatype-jsr310-2.13.1.jar:lib/synthea_uscore_v4/cql-engine-1.3.12.jar:lib/synthea_uscore_v4/cql-to-elm-1.3.17.jar:lib/synthea_uscore_v4/jackson-databind-2.13.1.jar:lib/synthea_uscore_v4/jackson-annotations-2.13.1.jar:lib/synthea_uscore_v4/jackson-core-2.13.1.jar:lib/synthea_uscore_v4/jackson-dataformat-csv-2.13.1.jar:lib/synthea_uscore_v4/snakeyaml-1.27.jar:lib/synthea_uscore_v4/commons-math3-3.6.1.jar:lib/synthea_uscore_v4/commons-text-1.9.jar:lib/synthea_uscore_v4/commons-validator-1.4.0.jar:lib/synthea_uscore_v4/cql-1.3.17.jar:lib/synthea_uscore_v4/elm-1.3.17.jar:lib/synthea_uscore_v4/model-1.3.17.jar:lib/synthea_uscore_v4/spring-web-5.2.7.RELEASE.jar:lib/synthea_uscore_v4/jaxb-api-2.4.0-b180830.0359.jar:lib/synthea_uscore_v4/jaxb-runtime-2.3.2.jar:lib/synthea_uscore_v4/javax.activation-api-1.2.0.jar:lib/synthea_uscore_v4/quick-1.3.17.jar:lib/synthea_uscore_v4/qdm-1.3.17.jar:lib/synthea_uscore_v4/jaxb2-basics-0.12.0.jar:lib/synthea_uscore_v4/jaxb2-basics-tools-0.12.0.jar:lib/synthea_uscore_v4/jcl-over-slf4j-1.7.33.jar:lib/synthea_uscore_v4/jul-to-slf4j-1.7.25.jar:lib/synthea_uscore_v4/slf4j-log4j12-1.7.25.jar:lib/synthea_uscore_v4/jsbml-1.5.jar:lib/synthea_uscore_v4/jsbml-arrays-1.5.jar:lib/synthea_uscore_v4/jsbml-comp-1.5.jar:lib/synthea_uscore_v4/jsbml-distrib-1.5.jar:lib/synthea_uscore_v4/jsbml-dyn-1.5.jar:lib/synthea_uscore_v4/jsbml-fbc-1.5.jar:lib/synthea_uscore_v4/jsbml-groups-1.5.jar:lib/synthea_uscore_v4/jsbml-render-1.5.jar:lib/synthea_uscore_v4/jsbml-layout-1.5.jar:lib/synthea_uscore_v4/jsbml-multi-1.5.jar:lib/synthea_uscore_v4/jsbml-qual-1.5.jar:lib/synthea_uscore_v4/jsbml-req-1.5.jar:lib/synthea_uscore_v4/jsbml-spatial-1.5.jar:lib/synthea_uscore_v4/jsbml-tidy-1.5.jar:lib/synthea_uscore_v4/jsbml-core-1.5.jar:lib/synthea_uscore_v4/biojava-ontology-4.0.0.jar:lib/synthea_uscore_v4/slf4j-api-1.7.33.jar:lib/synthea_uscore_v4/log4j-1.2-api-2.3.jar:lib/synthea_uscore_v4/log4j-core-2.17.0.jar:lib/synthea_uscore_v4/commons-math-2.2.jar:lib/synthea_uscore_v4/jfreechart-1.5.0.jar:lib/synthea_uscore_v4/json-smart-2.3.jar:lib/synthea_uscore_v4/commons-lang3-3.12.0.jar:lib/synthea_uscore_v4/httpclient-4.5.13.jar:lib/synthea_uscore_v4/commons-codec-1.15.jar:lib/synthea_uscore_v4/batik-codec-1.9.jar:lib/synthea_uscore_v4/batik-rasterizer-1.9.jar:lib/synthea_uscore_v4/batik-svgrasterizer-1.9.jar:lib/synthea_uscore_v4/batik-transcoder-1.9.jar:lib/synthea_uscore_v4/batik-bridge-1.9.jar:lib/synthea_uscore_v4/batik-script-1.9.jar:lib/synthea_uscore_v4/batik-anim-1.9.jar:lib/synthea_uscore_v4/batik-svg-dom-1.9.jar:lib/synthea_uscore_v4/batik-dom-1.9.jar:lib/synthea_uscore_v4/batik-css-1.9.jar:lib/synthea_uscore_v4/xmlgraphics-commons-2.2.jar:lib/synthea_uscore_v4/commons-io-2.11.0.jar:lib/synthea_uscore_v4/jsr305-3.0.2.jar:lib/synthea_uscore_v4/okhttp-3.8.1.jar:lib/synthea_uscore_v4/httpcore-4.4.13.jar:lib/synthea_uscore_v4/j2v8_macosx_x86_64-4.6.0.jar:lib/synthea_uscore_v4/j2v8_linux_x86_64-4.6.0.jar:lib/synthea_uscore_v4/j2v8_win32_x86_64-4.6.0.jar:lib/synthea_uscore_v4/j2v8_win32_x86-4.6.0.jar:lib/synthea_uscore_v4/commons-exec-1.3.jar:lib/synthea_uscore_v4/commons-beanutils-1.9.3.jar:lib/synthea_uscore_v4/commons-digester-1.8.jar:lib/synthea_uscore_v4/commons-logging-1.2.jar:lib/synthea_uscore_v4/hamcrest-all-1.3.jar:lib/synthea_uscore_v4/hamcrest-json-0.2.jar:lib/synthea_uscore_v4/jaxb-impl-2.3.0.1.jar:lib/synthea_uscore_v4/jaxb-core-2.3.0.1.jar:lib/synthea_uscore_v4/javax.activation-1.2.0.jar:lib/synthea_uscore_v4/eclipselink-2.6.0.jar:lib/synthea_uscore_v4/validation-api-1.1.0.Final.jar:lib/synthea_uscore_v4/antlr4-4.5.jar:lib/synthea_uscore_v4/jopt-simple-4.7.jar:lib/synthea_uscore_v4/ucum-1.0.2.jar:lib/synthea_uscore_v4/spring-beans-5.2.7.RELEASE.jar:lib/synthea_uscore_v4/spring-core-5.2.7.RELEASE.jar:lib/synthea_uscore_v4/stax-ex-1.8.1.jar:lib/synthea_uscore_v4/jakarta.xml.bind-api-2.3.2.jar:lib/synthea_uscore_v4/txw2-2.3.2.jar:lib/synthea_uscore_v4/istack-commons-runtime-3.0.8.jar:lib/synthea_uscore_v4/FastInfoset-1.2.16.jar:lib/synthea_uscore_v4/jakarta.activation-api-1.2.1.jar:lib/synthea_uscore_v4/log4j-api-2.17.0.jar:lib/synthea_uscore_v4/accessors-smart-1.2.jar:lib/synthea_uscore_v4/failureaccess-1.0.1.jar:lib/synthea_uscore_v4/listenablefuture-9999.0-empty-to-avoid-conflict-with-guava.jar:lib/synthea_uscore_v4/checker-qual-3.12.0.jar:lib/synthea_uscore_v4/error_prone_annotations-2.7.1.jar:lib/synthea_uscore_v4/j2objc-annotations-1.3.jar:lib/synthea_uscore_v4/okio-1.13.0.jar:lib/synthea_uscore_v4/batik-parser-1.9.jar:lib/synthea_uscore_v4/batik-gvt-1.9.jar:lib/synthea_uscore_v4/batik-svggen-1.9.jar:lib/synthea_uscore_v4/batik-awt-util-1.9.jar:lib/synthea_uscore_v4/batik-xml-1.9.jar:lib/synthea_uscore_v4/batik-util-1.9.jar:lib/synthea_uscore_v4/xalan-2.7.2.jar:lib/synthea_uscore_v4/serializer-2.7.2.jar:lib/synthea_uscore_v4/xml-apis-1.3.04.jar:lib/synthea_uscore_v4/jaxb2-basics-runtime-0.12.0.jar:lib/synthea_uscore_v4/javaparser-1.0.11.jar:lib/synthea_uscore_v4/jsonassert-1.1.1.jar:lib/synthea_uscore_v4/json-simple-1.1.1.jar:lib/synthea_uscore_v4/junit-4.12.jar:lib/synthea_uscore_v4/hamcrest-core-1.3.jar:lib/synthea_uscore_v4/log4j-1.2.17.jar:lib/synthea_uscore_v4/javax.persistence-2.1.0.jar:lib/synthea_uscore_v4/commonj.sdo-2.1.1.jar:lib/synthea_uscore_v4/javax.json-1.0.4.jar:lib/synthea_uscore_v4/antlr4-runtime-4.5.jar:lib/synthea_uscore_v4/ST4-4.0.8.jar:lib/synthea_uscore_v4/antlr-runtime-3.5.2.jar:lib/synthea_uscore_v4/xpp3-1.1.4c.jar:lib/synthea_uscore_v4/xpp3_xpath-1.1.4c.jar:lib/synthea_uscore_v4/spring-jcl-5.2.7.RELEASE.jar:lib/synthea_uscore_v4/woodstox-core-5.0.1.jar:lib/synthea_uscore_v4/jigsaw-2.2.6.jar:lib/synthea_uscore_v4/xstream-1.4.9.jar:lib/synthea_uscore_v4/staxmate-2.3.0.jar:lib/synthea_uscore_v4/jtidy-r938.jar:lib/synthea_uscore_v4/asm-5.0.4.jar:lib/synthea_uscore_v4/batik-ext-1.9.jar:lib/synthea_uscore_v4/xml-apis-ext-1.3.04.jar:lib/synthea_uscore_v4/batik-constants-1.9.jar:lib/synthea_uscore_v4/batik-i18n-1.9.jar:lib/synthea_uscore_v4/json-20090211.jar:lib/synthea_uscore_v4/commons-collections-3.2.2.jar:lib/synthea_uscore_v4/org.abego.treelayout.core-1.0.1.jar:lib/synthea_uscore_v4/stax2-api-3.1.4.jar:lib/synthea_uscore_v4/xmlpull-1.1.3.1.jar:lib/synthea_uscore_v4/xpp3_min-1.1.4c.jar'
  CONFIG='--exporter.fhir.use_us_core_ig=true --exporter.baseDirectory=./output/raw --exporter.hospital.fhir.export=true --exporter.practitioner.fhir.export=true --exporter.groups.fhir.export=true'
end

if MRBURNS
  system( "java -cp #{CLASSPATH} App -s #{RAND_SEED} -a 80-81 -g M -p 50 #{CONFIG} --exporter.years_of_history=0 > output/synthea.log" )
else
  system( "java -cp #{CLASSPATH} App -s #{RAND_SEED} -p 160 #{CONFIG} > output/synthea.log" )
  # system( "java -cp #{CLASSPATH} App -s #{RAND_SEED} -p 10 #{CONFIG} > output/synthea.log" )
end
tok = Time.now.to_i
puts "  Generated data in #{DataScript::TimeUtilities.pretty(tok - start)}."

puts 'Loading FHIR Bundles...'
records = []
all_group = nil
input_folder = File.join(File.dirname(__FILE__), './output/raw/fhir')
Dir.foreach(input_folder) do |file|
  next unless file.end_with?('.json')
  next if VERSION == 3 && file.start_with?('hospitalInformation', 'practitionerInformation')
  json = File.open("#{input_folder}/#{file}", 'r:UTF-8', &:read)
  bundle = FHIR.from_contents(json)
  if bundle.resourceType == 'Group'
    all_group = bundle
  elsif bundle.resourceType == 'Bundle'
    records << bundle
  end
end
tik = Time.now.to_i
puts "  Loaded #{records.length} FHIR Bundles in #{DataScript::TimeUtilities.pretty(tik - tok)}."

# Constraints to test
constraints = DataScript::Constraints.new
# Selections (plural) is the patient bundles selected that satisfy the constraints
selections = []
# Selection (singular) is the latest selected patient bundle
selection = nil
# Satsified is the list of the named constraints (as strings) that the current selections satisfy.
satisfied = []
# Unsatisfied is the list of the named constraints (as strings) that have yet to be satisified.
unsatisfied = DataScript::Constraints::CONSTRAINTS.keys - satisfied

puts 'Selecting patients by constraints...'
# while there are more constraints to satisfy, there are still patient records remaining to choose from,
# or the remaining patient records are still useful (e.g. they are satisfying additional constraints)
until unsatisfied.empty? || records.empty? || selection&.total == 0
  # Score each patient against the unsatisfied constraints
  puts '  Scoring Records...'
  records.each do |bundle|
    constraints.satisfied?([bundle], unsatisfied)
    bundle.total = unsatisfied.length - constraints.violations.length
  end

  # Sort the patients, first worse, last best
  # and select the patient that satisfies the most remaining constraints
  records.sort! {|a, b| a.total <=> b.total}
  # puts "  #{records.map {|b| b.total}}" # debug scores
  selection = records.pop

  # Recalculate constraint satisfaction variables
  constraints.satisfied?([selection])
  selection_unsatisfied = constraints.violations
  selection_satisfied = DataScript::Constraints::CONSTRAINTS.keys - selection_unsatisfied

  satisfied = satisfied.append(selection_satisfied).flatten.uniq
  unsatisfied = DataScript::Constraints::CONSTRAINTS.keys - satisfied

  # Add the currently selected patient to our list, as long as it is a useful addition
  if selection.total > 0
    puts "    Selected: #{selection_satisfied}"
    selections << selection
  else
    puts "    Done."
  end
end
selections.each {|bundle| bundle.total = nil}

# How many profiles are supported?
selection = nil
profiles_present = constraints.profiles_present(selections)
profiles_present.append('http://hl7.org/fhir/us/core/StructureDefinition/us-core-medication') if MRBURNS
profiles_missing = DataScript::Constraints::REQUIRED_PROFILES - profiles_present
puts 'Selecting patients by profile...' unless profiles_missing.empty?

until profiles_missing.empty? || records.empty? || selection&.total == 0
  # Score each patient against the unsatisfied constraints
  puts '  Scoring Records...'
  records.each do |bundle|
    bundle_present = constraints.profiles_present([bundle])
    bundle.total = (bundle_present - profiles_present).length
  end

  # Sort the patients, first worse, last best
  # and select the patient that satisfies the most remaining constraints
  records.sort! {|a, b| a.total <=> b.total}
  # puts "  #{records.map {|b| b.total}}" # debug scores
  selection = records.pop

  bundle_present = constraints.profiles_present([selection])
  bundle_extras = bundle_present - profiles_present
  profiles_present = profiles_present.append(bundle_present).flatten.uniq
  profiles_missing = DataScript::Constraints::REQUIRED_PROFILES - profiles_present
  if selection.total > 0
    puts "    Selected: #{bundle_extras}"
    selections << selection
  else
    puts "    Done."
  end
end
selections.each {|bundle| bundle.total = nil}

tok = Time.now.to_i
puts "  Selected #{selections.length} patients (#{DataScript::TimeUtilities.pretty(tok - tik)})."

# post-process selections
puts 'Modifying selected patients...'
patient_bundle_absent_name = DataScript::Modifications.modify!(selections, RAND_SEED)
tik = Time.now.to_i
puts "  Modified patients (#{DataScript::TimeUtilities.pretty(tik - tok)})."
group = selections.pop

puts 'Prefilter constraint testing...'
if constraints.satisfied?(selections)
  puts '  All constraints satisfied.'
else
  error("  #{constraints.violations.length} remaining constraints violated: #{constraints.violations}")
end
profiles_present = constraints.profiles_present(selections)
profiles_missing = DataScript::Constraints::REQUIRED_PROFILES - profiles_present
if profiles_missing.empty?
  puts '  All profiles present.'
else
  error("  Missing #{profiles_missing.length} profiles:")
  profiles_missing.each {|p| error("    * #{p}")}
end

puts 'Filtering selected patient data...'
DataScript::Filter.filter!(selections)
tok = Time.now.to_i
puts "  Filtered data (#{DataScript::TimeUtilities.pretty(tok - tik)})."

puts 'Final constraint testing...'
if constraints.satisfied?(selections)
  puts '  All constraints satisfied.'
else
  error("  #{constraints.violations.length} remaining constraints violated: #{constraints.violations}")
end
profiles_present = constraints.profiles_present(selections)
profiles_missing = DataScript::Constraints::REQUIRED_PROFILES - profiles_present
if profiles_missing.empty?
  puts '  All profiles present.'
else
  error("  Missing #{profiles_missing.length} profiles:")
  profiles_missing.each {|p| error("    * #{p}")}
end

# Add the Group back
selections << group
# Remove the patient with primitive extensions
# because we need to write out their JSON separately.
if patient_bundle_absent_name
  selections.delete(patient_bundle_absent_name)
  records.delete(patient_bundle_absent_name)
end

# Save selections
tik = Time.now.to_i
output_data = 'output/data'
output_validation = 'output/validation'

puts "Overwriting selections into ./#{output_data}"
Dir.mkdir(output_data) unless File.exists?(output_data)
FileUtils.rm Dir.glob("./#{output_data}/*.json")

Dir.mkdir(output_validation) unless File.exists?(output_validation)
FileUtils.rm Dir.glob("./#{output_validation}/*.txt")

selections.each do |bundle|
  if bundle.resourceType == 'Bundle'
    id = bundle.entry.first.resource.id
  else
    id = bundle.id
  end
  filename = "#{output_data}/#{id}.json"
  file = File.open(filename,'w:UTF-8')
  json_string = bundle.to_json
  # json_string.gsub!('"value": "DATAABSENTREASONEXTENSIONGOESHERE"', "\"_value\": { \"extension\": [ #{DataScript::Modifications.data_absent_reason.to_json} ] }")
  file.write( json_string )
  file.close
end

patient_without_name_json = nil
if patient_bundle_absent_name
  # we need to manually manipulate the JSON for this one bundle,
  # because the fhir_models gem does not support primitive extensions.
  json = JSON.parse( patient_bundle_absent_name.to_json )
  json['entry'][0]['resource']['name'] = [{
    '_family' => {
      'extension' => [ DataScript::Modifications.data_absent_reason.to_hash ]
    },
    '_given' => [{
      'extension' => [ DataScript::Modifications.data_absent_reason.to_hash ]
    }]
  }]
  patient_without_name_json = JSON.unparse(json['entry'][0]['resource'])
  json = JSON.pretty_unparse(json)
  # json.gsub!('"value": "DATAABSENTREASONEXTENSIONGOESHERE"', "\"_value\": { \"extension\": [ #{DataScript::Modifications.data_absent_reason.to_json} ] }")
  filename = "#{output_data}/#{patient_bundle_absent_name.entry.first.resource.id}.json"
  file = File.open(filename,'w:UTF-8')
  file.write(json)
  file.close
  # run FHIR validator on output
  puts 'Running FHIR validator on output.'
  validation_file = "#{output_validation}/#{patient_bundle_absent_name.entry.first.resource.id}.txt"
  validate(filename, validation_file)
end

tok = Time.now.to_i
puts "  Saved #{selections.length + (patient_bundle_absent_name ? 1 : 0)} files (#{DataScript::TimeUtilities.pretty(tok - tik)})."

# Save the selection records in the Bulk Data Format
tik = Time.now.to_i

puts 'Saving *selected* records in Bulk Data ndjson format...'
converter = DataScript::BulkDataConverter.new('selected')
selections.each do |bundle|
  converter.convert_to_bulk_data(bundle)
end
converter.convert_to_bulk_data(patient_bundle_absent_name, patient_without_name_json) if patient_bundle_absent_name
converter.close

tok = Time.now.to_i
puts "  Saved #{selections.length + (patient_bundle_absent_name ? 1 : 0)} records as ndjson (#{DataScript::TimeUtilities.pretty(tok - tik)})."

# Save *ALL* the records in the Bulk Data Format
unless MRBURNS
  tik = Time.now.to_i

  puts 'Saving *all* records in Bulk Data ndjson format...'
  converter = DataScript::BulkDataConverter.new('all')
  records.each do |bundle|
    converter.convert_to_bulk_data(bundle)
  end
  converter.convert_to_bulk_data(patient_bundle_absent_name, patient_without_name_json) if patient_bundle_absent_name
  converter.convert_to_bulk_data(group)
  converter.convert_to_bulk_data(all_group)
  converter.close

  tok = Time.now.to_i
  puts "  Saved #{records.length + (patient_bundle_absent_name ? 1 : 0)} records as ndjson (#{DataScript::TimeUtilities.pretty(tok - tik)})."
end

puts 'Cleaning...'
['Claim','ExplanationOfBenefit','ImagingStudy'].each do |resourceType|
  FileUtils.rm Dir.glob("./#{output}/**/#{resourceType}.ndjson")
end

# Validating
tik = Time.now.to_i
puts "Validating... Output logged in ./#{output_validation}"
selections.each do |bundle|
  if bundle.resourceType == 'Bundle'
    id = bundle.entry.first.resource.id
  else
    id = bundle.id
  end
  # run FHIR validator on output
  filename = "#{output_data}/#{id}.json"
  validation_file = "#{output_validation}/#{id}.txt"
  validate(filename, validation_file)
end

if patient_bundle_absent_name
  filename = "#{output_data}/#{patient_bundle_absent_name.entry.first.resource.id}.json"
  # run FHIR validator on output
  validation_file = "#{output_validation}/#{patient_bundle_absent_name.entry.first.resource.id}.txt"
  validate(filename, validation_file)
end
tok = Time.now.to_i
puts "  Validated #{selections.length + (patient_bundle_absent_name ? 1 : 0)} files (#{DataScript::TimeUtilities.pretty(tok - tik)})."

# Print the amount of time it took...
stop = Time.now.to_i
puts "Complete (#{DataScript::TimeUtilities.pretty(stop - start)})"
