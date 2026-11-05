#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative 'lib/nicherank'

if $PROGRAM_NAME == __FILE__
  root = File.expand_path('../..', __dir__)
  NicheRank.load_openalex_key(File.join(root, '.env.local'))
  queries = {
    'Ryan Huang' => ['Gray Failure The Achilles Heel of Cloud Scale Systems', 'https://web.eecs.umich.edu/~ryanph/'],
    'Michael Kim' => ['Calibrating Predictions to Decisions A Novel Approach to Multi Class Calibration', 'https://www.cs.cornell.edu/~mpkim/pubs.html'],
    'YuFeng (Kevin) Chen' => ['Collision Resilient Insect Scale Soft Actuated Aerial Robots with High Agility', 'https://smrl.mit.edu/publications/'],
    'Kartik Goyal' => ['Cascaded Information Disclosure for Generalized Evaluation of Problem Solving Capabilities', 'https://kartikgo.github.io/'],
    'Will Perkins' => ['Sampling from the random cluster model at all temperatures on random graphs', 'https://willperkins.org/'],
    'Merrick Furst' => ['Parity circuits and the polynomial time hierarchy', 'https://www.cc.gatech.edu/people/merrick-furst'],
    'Ji Zhang' => ['LOAM Lidar Odometry and Mapping in Real time', 'https://www.ri.cmu.edu/ri-faculty/ji-zhang/'],
    'Wei Hu' => ['The Surprising Simplicity of the Early-Time Learning Dynamics of Neural Networks', 'https://weihu.me/'],
    'Gang Wang' => ['PurpCode Reasoning for Safer Code Generation', 'https://gangw.cs.illinois.edu/'],
    'Bo Li' => ['DecodingTrust A Comprehensive Assessment of Trustworthiness in GPT Models', 'https://aisecure.github.io/'],
    'Hao Peng' => ['RoPE at the End of Its Rope Theory Diagnosis and Mitigation of Long Context Failures', 'https://haopeng-nlp.github.io/']
  }
  client = NicheRank::Client.new(cache: File.join(root, 'tmp/openalex_cache'), max_requests: 30)
  queries.each do |name, (query, evidence)|
    path = File.join(root, 'tmp/identity_works', Digest::SHA256.hexdigest(name) + '.json')
    next if File.exist?(path)
    result = client.get('works', 'search' => query, 'per_page' => 5, 'select' => 'id,title,authorships,doi,publication_year')
    NicheRank.atomic_json(path, { 'name' => name, 'query' => query, 'source' => evidence, 'results' => result.fetch('results') })
    puts "#{name}: #{result.fetch('results').size} publication candidates"
    $stdout.flush
  end
end
