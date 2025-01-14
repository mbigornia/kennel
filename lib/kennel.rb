# frozen_string_literal: true
require "faraday"
require "json"
require "English"

require "kennel/version"
require "kennel/utils"
require "kennel/progress"
require "kennel/syncer"
require "kennel/api"
require "kennel/github_reporter"
require "kennel/subclass_tracking"
require "kennel/settings_as_methods"
require "kennel/file_cache"
require "kennel/template_variables"
require "kennel/optional_validations"
require "kennel/unmuted_alerts"

require "kennel/models/base"
require "kennel/models/record"

# records
require "kennel/models/dashboard"
require "kennel/models/monitor"
require "kennel/models/slo"

# settings
require "kennel/models/project"
require "kennel/models/team"

module Kennel
  class ValidationError < RuntimeError
  end

  @out = $stdout
  @err = $stderr

  class << self
    attr_accessor :out, :err

    def generate
      store generated
    end

    def plan
      syncer.plan
    end

    def update
      syncer.plan
      syncer.update if syncer.confirm
    end

    private

    def store(parts)
      Progress.progress "Storing" do
        old = Dir["generated/**/*"]
        used = []

        Utils.parallel(parts, max: 2) do |part|
          path = "generated/#{part.tracking_id.tr("/", ":").sub(":", "/")}.json"
          used << File.dirname(path) # only 1 level of sub folders, so this is safe
          used << path
          write_file_if_necessary(path, JSON.pretty_generate(part.as_json) << "\n")
        end

        # deleting all is slow, so only delete the extras
        (old - used).each { |p| FileUtils.rm_rf(p) }
      end
    end

    def write_file_if_necessary(path, content)
      # 99% case
      begin
        return if File.read(path) == content
      rescue Errno::ENOENT
        FileUtils.mkdir_p(File.dirname(path))
      end

      # slow 1% case
      File.write(path, content)
    end

    def syncer
      @syncer ||= Syncer.new(api, generated, project: ENV["PROJECT"])
    end

    def api
      @api ||= Api.new(ENV.fetch("DATADOG_APP_KEY"), ENV.fetch("DATADOG_API_KEY"))
    end

    def generated
      @generated ||= begin
        Progress.progress "Generating" do
          load_all
          parts = Models::Project.recursive_subclasses.flat_map do |project_class|
            project_class.new.validated_parts
          end
          parts.group_by(&:tracking_id).each do |tracking_id, same|
            next if same.size == 1
            raise <<~ERROR
              #{tracking_id} is defined #{same.size} times
              use a different `kennel_id` when defining multiple projects/monitors/dashboards to avoid this conflict
            ERROR
          end
          parts
        end
      end
    end

    def load_all
      ["teams", "parts", "projects"].each do |folder|
        Dir["#{folder}/**/*.rb"].sort.each { |f| require "./#{f}" }
      end
    end
  end
end
