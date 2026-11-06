class AniCliFr < Formula
  desc "CLI pour regarder des animes en VF/VOSTFR (anime-sama, voir-anime)"
  homepage "https://github.com/TTVNaylek/ani-cli-fr"
  url "https://github.com/TTVNaylek/ani-cli-fr/archive/refs/tags/v0.4.0.tar.gz"
  sha256 "ce4e8f4c684a620d3bfed707c94f99e763a554229abbffec63e5070588c22024"
  license "MIT"

  depends_on "curl"
  depends_on "fzf"
  depends_on "mpv"
  depends_on "yt-dlp"

  def install
    # Le script suit les liens symboliques et cherche "providers" a cote de
    # lui : on garde les deux dans libexec et on expose un lien dans bin.
    libexec.install "ani-cli-fr", "providers"
    bin.install_symlink libexec/"ani-cli-fr"
  end

  test do
    system bin/"ani-cli-fr", "--help"
  end
end
