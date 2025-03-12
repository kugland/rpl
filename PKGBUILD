# Maintainer: André Kugland <akugland@example.com>
pkgname=rpl
pkgver=3.1.0
pkgrel=1
pkgdesc="Rename files using Perl expressions"
arch=('any')
url="https://github.com/kugland/rpl"
license=('MIT')
depends=('perl' 'perl-getopt-long' 'perl-text-unidecode')
makedepends=('perl-test-exception')
checkdepends=('perl-test-exception')
source=("rpl" "rpl.t" "README.md" ".proverc")
sha256sums=('SKIP' 'SKIP' 'SKIP' 'SKIP')

package() {
  cd "$srcdir"
  install -Dm755 rpl "$pkgdir/usr/bin/rpl"
  install -Dm644 README.md "$pkgdir/usr/share/doc/$pkgname/README.md"
}

check() {
  cd "$srcdir"
  export LC_ALL=C.UTF-8
  export LANG=C.UTF-8
  export PATH="$PATH:/usr/bin/core_perl"
  prove -v rpl.t
}
