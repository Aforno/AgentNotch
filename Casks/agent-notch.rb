cask "agent-notch" do
  version "0.2.1"
  sha256 "cbe22bb2de25d3a6d2ca2a364465a249fa4d1dff7f4ac16edf14661fe9ece9fa"

  url "https://github.com/Aforno/AgentNotch/releases/download/v#{version}/Agent-Notch-#{version}-macOS-arm64.zip"
  name "Agent Notch"
  desc "Notch status surface for local coding agents"
  homepage "https://github.com/Aforno/AgentNotch"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :sonoma
  depends_on arch: :arm64

  app "Agent Notch.app"

  zap trash: [
    "~/.agentnotch",
    "~/Library/Application Support/AgentNotch",
    "~/Library/Preferences/com.afonsoferreira.AgentNotch.plist",
  ]

  caveats <<~EOS
    Preview releases may be ad-hoc signed. macOS Gatekeeper can block the first
    launch. If that happens, Control-click the app, choose Open, and confirm.
  EOS
end
