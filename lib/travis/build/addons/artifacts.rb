require 'travis/build/addons/base'

module Travis
  module Build
    class Addons
      class Artifacts < Base
        SUPER_USER_SAFE = true

        CONCURRENCY = 5
        MAX_SIZE = Float(1024 * 1024 * 50)

        def after_script
          return if config.empty?
          sh.newline

          if pull_request?
            sh.echo 'Artifacts support disabled for pull requests'
            return
          end

          unless branch_runnable?
            sh.echo "Artifacts support not enabled for the current branch (#{data.branch.inspect})"
            return
          end

          run
        end

        private

        def run
          override_controlled_params
          options = config.delete(:options)

          return unless validate!

          sh.echo 'Uploading Artifacts (BETA)', ansi: :yellow
          sh.fold 'artifacts.0' do
            install
            configure_env
            sh.set 'PATH', '$HOME/bin:$PATH', echo: false
          end
          sh.cmd "artifacts upload #{options}", assert: false
          sh.echo 'Done uploading artifacts', ansi: :yellow
        end

        def branch
          config[:branch]
        end

        def pull_request?
          data.pull_request
        end

        def branch_runnable?
          return true if branch.nil?
          return branch.include?(data.branch) if branch.respond_to?(:each)
          branch == data.branch
        end

        def install
          sh.cmd install_script, echo: false, assert: false
        end

        def install_script
          @install_script ||= <<-EOF.gsub(/^\s{12}/, '')
            ARTIFACTS_DEST=$HOME/bin/artifacts
            OS=$(uname | tr '[:upper:]' '[:lower:]')
            ARCH=$(uname -m)
            if [[ $ARCH == x86_64 ]] ; then
              ARCH=amd64
            fi
            mkdir -p $(dirname "$ARTIFACTS_DEST")
            curl -sL -o "$ARTIFACTS_DEST" \
                https://s3.amazonaws.com/meatballhat/artifacts/stable/build/$OS/$ARCH/artifacts
            chmod +x "$ARTIFACTS_DEST"
            PATH="$(dirname "$ARTIFACTS_DEST"):$PATH" artifacts -v
          EOF
        end

        def override_controlled_params
          %w(max_size concurrency target_paths).map(&:to_sym).each do |k|
            config.delete(k)
          end
          config[:max_size] = MAX_SIZE
          config[:concurrency] = CONCURRENCY
          config[:target_paths] = target_paths
        end

        def target_paths
          @target_paths ||= File.join(
            data.slug,
            data.build[:number],
            data.job[:number]
          )
        end

        def configure_env
          config[:paths] ||= '$(git ls-files -o | tr "\n" ":")'
          config[:log_format] ||= 'multiline'

          config.each { |key, value| set_env(key.to_s.upcase, value) }
        end

        def set_env(key, value, prefix = 'ARTIFACTS_')
          value = value.map(&:to_s).join(':') if value.respond_to?(:each)
          sh.set "#{prefix}#{key}", %Q{"#{value}"}, echo: setenv_echoable?(key)
        end

        def setenv_echoable?(key)
          %w(PATHS).include?(key)
        end

        def validate!
          valid = true
          unless config[:key]
            sh.echo 'Artifacts config missing :key param', ansi: :red
            valid = false
          end
          unless config[:secret]
            sh.echo 'Artifacts config missing :secret param', ansi: :red
            valid = false
          end
          unless config[:bucket]
            sh.echo 'Artifacts config missing :bucket param', ansi: :red
            valid = false
          end
          valid
        end
      end
    end
  end
end
