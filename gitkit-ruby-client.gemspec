# encoding: utf-8
# Copyright 2014 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

Gem::Specification.new do |s|
  s.name = "identity-toolkit-ruby-client"
  s.version = "1.0.2"

  s.authors = ["Jin Liu"]
  s.homepage = "https://developers.google.com/identity-toolkit/v3"
  s.summary = 'Google Identity Toolkit Ruby client'
  s.description = 'Google Identity Toolkit Ruby client library'
  s.extra_rdoc_files = ["README.rdoc"]
  s.files = ["lib/gitkit_client.rb", "lib/rpc_helper.rb", "README.rdoc"]

  if s.respond_to? :specification_version then
    s.specification_version = 4

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<addressable>, [">= 2.3.2"])
      s.add_runtime_dependency(%q<faraday>, [">= 0.9.0"])
      s.add_runtime_dependency(%q<multi_json>, [">= 1.0.0"])
      s.add_runtime_dependency(%q<jwt>, [">= 1.0.0"])
    else
      s.add_dependency(%q<addressable>, [">= 2.3.2"])
      s.add_dependency(%q<faraday>, [">= 0.9.0"])
      s.add_dependency(%q<multi_json>, [">= 1.0.0"])
      s.add_dependency(%q<jwt>, [">= 1.0.0"])
    end
  else
    s.add_dependency(%q<addressable>, [">= 2.3.2"])
    s.add_dependency(%q<faraday>, [">= 0.9.0"])
    s.add_dependency(%q<multi_json>, [">= 1.0.0"])
    s.add_dependency(%q<jwt>, [">= 1.0.0"])
  end
end
