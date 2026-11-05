class Carrier < Formula
  desc "Autonomous epic orchestrator: ships and reviews Solve epics with AI agents"
  homepage "https://github.com/AshuLab/carrier"
  url "https://registry.npmjs.org/@ashulab/carrier/-/carrier-0.1.0.tgz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"

  depends_on "gh"
  depends_on "git"
  depends_on "node"

  def install
    system "npm", "install", *std_npm_args
    bin.install_symlink libexec.glob("bin/*")
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/carrier --version")
  end
end
