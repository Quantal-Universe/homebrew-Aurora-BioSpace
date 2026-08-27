class AuroraBiospace < Formula
  desc "Launcher for the Aurora Bioscience Dashboard by Quantal-Universe, founded by Codemaster-AR."
  homepage "https://github.com/Quantal-Universe/Aurora-BioSpace"
  url "https://github.com/Quantal-Universe/Aurora-BioSpace/archive/refs/tags/v8.0.0.tar.gz"
  sha256 "c9d7222fadc31921dd82ccbab6e88f75818f06229894664fd5395e59258ccafb"
  version "8.0.0"

  depends_on "node"
  depends_on "python@3.12"

  # Tell Homebrew to leave ALL of libexec alone —
  # Electron ships pre-built dylibs that can't be relinked
  skip_clean "libexec"

  # --- CRITICAL: LINUX SYSTEM LIBRARIES ---
  on_linux do
    depends_on "libx11"
    depends_on "libxkbfile"
    depends_on "libsecret"
    depends_on "nss"
    depends_on "atk"
    depends_on "at-spi2-atk"
    depends_on "cups"
    depends_on "gtk+3"
    depends_on "libdrm"
    depends_on "mesa"
    depends_on "alsa-lib"
  end

  def install
    # 1. UNPACK BOTH LAYERS CLEANLY
    nested_tarball = Dir.glob("**/*.tar.gz").reject { |f| f.include?("Old/") }.first
    if nested_tarball
      ohai "Extracting primary production package branch layer..."
      system "tar", "-xzf", nested_tarball
    end

    # 2. LOCATE ASSET TREE BRANCHES
    package_json = Dir.glob("**/genelab/package.json").first || Dir.glob("**/package.json").first
    odie "Error: Could not locate workspace package data configuration." if package_json.nil?

    app_source_dir = File.dirname(package_json)

    # 3. CONFIGURE ALL DEPENDENCIES (including devDependencies for electron)
    cd app_source_dir do
      system "npm", "install"
    end

    # 4. CAPTURE EXISTING REPO LAUNCHER BEFORE WRITING RE-MAPS
    native_launcher = Dir.glob("**/genelab-launcher.py").first
    odie "Error: Could not find genelab-launcher.py in the source archive." if native_launcher.nil?

    # 5. SET UP VIRTUALENV AND AUTO-INSTALL PYTHON DEPENDENCIES
    python_exe = Formula["python@3.12"].opt_bin/"python3.12"
    venv = libexec/"venv"
    ohai "Creating Python virtual environment..."
    system python_exe, "-m", "venv", venv
    ohai "Installing required Python packages (rich, requests)..."
    system venv/"bin/pip", "install", "--quiet", "rich", "requests"

    venv_python = venv/"bin/python3"

    launcher_content = File.read(native_launcher)

    # Strip away any existing shebang headers cleanly
    if launcher_content.start_with?("#!")
      launcher_content = launcher_content.lines[1..].join
    end

    # Inject the venv Python path into the shebang
    File.write(native_launcher, "#!#{venv_python}\n" + launcher_content)
    system "chmod", "+x", native_launcher

    # 6. MOVE RUNTIME DIRECTORY TREE TO CLEAN ISOLATED LIBEXEC
    outer_workspace = File.dirname(native_launcher)
    cd outer_workspace do
      libexec.install Dir["*"]
    end

    # 7. CLEAR DESKTOP APP QUARANTINE FLAGS (macOS only)
    # Scoped to just genelab app — avoids hitting SIP-protected venv symlinks
    if OS.mac?
      system "xattr", "-rd", "com.apple.quarantine", (libexec/"genelab").to_s rescue nil
    end

    # 8. WRITE CUSTOM SHELL WRAPPER — injects node_modules/.bin into PATH
    # so that electron is found when npm start runs
    (bin/"aurora-biospace").write <<~EOS
      #!/bin/bash
      export PATH="#{libexec}/genelab/node_modules/.bin:$PATH"
      exec "#{libexec}/venv/bin/python3" "#{libexec}/genelab-launcher.py" "$@"
    EOS
    chmod 0755, bin/"aurora-biospace"
  end

  test do
    assert_predicate bin/"aurora-biospace", :exist?
  end
end
