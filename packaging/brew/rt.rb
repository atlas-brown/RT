class Rt < Formula
  desc 'Overlay type system for Unix shell pipelines'
  homepage 'https://github.com/atlas-brown/rt'
  version '0.1.0'
  license :cannot_represent
  url "https://github.com/atlas-brown/rt/archive/refs/tags/v#{version}.tar.gz"
  sha256 ''

  depends_on 'docker' => :test

  def install
    bin.install 'scripts/run-in-container.sh' => 'rt'
    bin.install_symlink 'rt' => 'rti'
  end

  def caveats
    <<~EOS
      rt and rti require Docker.

        Install Docker: https://docs.docker.com/get-docker/

    EOS
  end

  test do
    assert_predicate bin / 'rt', :executable?
    assert_predicate bin / 'rti', :executable?
    assert_match 'docker', File.read(bin / 'rt')
  end
end
