<services>
  <service name="download_url">
    <param name="url">https://github.com/emacs-mirror/emacs/archive/refs/heads/emacs-29.tar.gz</param>
    <param name="filename">emacs-29.tar.gz</param>
  </service>
  <service name="download_url">
    <param name="url">https://raw.githubusercontent.com/emacs-mirror/emacs/master/configure.ac</param>
    <param name="filename">configure.ac</param>
  </service>
  <service name="sed">
    <param name="default-print">off</param>
    <param name="expression">/^[[:space:]]*AC_INIT[[:space:]]*\(/ {
      s/^[[:space:]]*AC_INIT[[:space:]]*\([[:space:]]*((\[[^]]*\])|[^,])*,[[:space:]]*\[?[[:space:]]*([-0-9.a-zA-Z+_]+)([[:space:]]|\]|,).*$/\3/p
      t quit
      b
      : quit
      q
    }
    $ a 29.0.0
    </param>
    <param name="file">_server:download_url:configure.ac</param>
    <param name="out">version.stamp</param>
    <param name="missing-input">empty-safe</param>
  </service>
  <service name="set_version" mode="trylocal">
    <param name="file">emacs.spec</param>
    <param name="fromfile">version.stamp</param>
    <param name="regex">(.*)</param>
  </service>
</services>
