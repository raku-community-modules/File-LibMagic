use v6;
use NativeCall;

unit class File::LibMagic;

my class X is Exception {
    has $!message;
    submethod BUILD (:$!message) { }
    method message {
        return "error from libmagic: $!message";
    }
}

my class Cookie is repr('CPointer') {
    method new (int32 $flags, Cool @magic-files) returns Cookie {
        my $cookie = magic_open($flags)
            or X.new('out of memory').throw;

        my $files = @magic-files.elems ?? @magic-files.join(':') !! (Str);
        my $ok = magic_load( $cookie, $files );
        unless $ok >= 0 {
            X.new( magic_error($cookie) ).throw;
        }

        return $cookie;
    }
    sub magic_open (int32) returns Cookie is native('magic', v1) { * }
    sub magic_load (Cookie, Str) returns int32 is native('magic', v1) { * }

    method DESTROY is native('magic', v1) is symbol('magic_close') { * }

    # It's a lot easier to just read this much data in and then call
    # magic_buffer than it is to try to actually pass a Perl handle to
    # magic_descriptor.
    #
    # The BUFSIZE is how much data libmagic will want, so we just pass that
    # much.
    my \BUFSIZE = 256 * 1024;
    method magic-descriptor (int32 $flags, IO::Handle $file) returns Str {
        $file.seek(0);
        my $buffer = $file.read(BUFSIZE);
        return self.magic-buffer( $flags, $buffer );
    }

    method magic-file (int32 $flags, Cool $filename) returns Str {
        self.setflags($flags);
        # We need the .Str to turn things like an IO::Path into an actual Str
        # for the benefit of NativeCall.
        return magic_file( self, $filename.Str )
            // self.throw-error;
    }
    sub magic_file (Cookie, Str) returns Str is native('magic', v1) { * }

    # I tried making magic-buffer a multi method with magic_buffer as a
    # corresponding multi sub but I kept getting errors about signatures not
    # matching. I'll go the ugly but working route for now.
    method magic-string (int32 $flags, Str $buffer) returns Str {
        self.setflags($flags);
        return magic_string( self, $buffer, $buffer.encode('UTF-8').elems )
            // self.throw-error;
    }
    sub magic_string (Cookie, Str, int32) returns Str is native('magic', v1) is symbol('magic_buffer') { * }

    method magic-buffer (int32 $flags, Buf[uint8] $buffer) returns Str {
        self.setflags($flags);

        my $c-array = CArray[uint8].new;
        $c-array[$_] = $buffer[$_] for ^$buffer.elems;

        return magic_buffer( self, $c-array, $buffer.elems )
            // self.throw-error;
    }
    sub magic_buffer (Cookie, CArray[uint8], int32) returns Str is native('magic', v1) { * }

    method setflags(int32 $flags) {
        magic_setflags(self, $flags);
    }
    sub magic_setflags (Cookie, int32) is native('magic', v1) { * }

    method throw-error {
        X.new( message => magic_error(self) ).throw;
    }
    sub magic_error (Cookie) returns Str is native('magic', v1) { * }
}

has Cookie $!cookie;
has int $!flags;
has Cool @magic-files;

# Copied from /usr/include/magic.h on my system
my \MAGIC_NONE               = 0x000000; #  No flags 
my \MAGIC_DEBUG              = 0x000001; #  Turn on debugging 
my \MAGIC_SYMLINK            = 0x000002; #  Follow symlinks 
my \MAGIC_COMPRESS           = 0x000004; #  Check inside compressed files 
my \MAGIC_DEVICES            = 0x000008; #  Look at the contents of devices 
my \MAGIC_MIME_TYPE          = 0x000010; #  Return the MIME type 
my \MAGIC_CONTINUE           = 0x000020; #  Return all matches 
my \MAGIC_CHECK              = 0x000040; #  Print warnings to stderr 
my \MAGIC_PRESERVE_ATIME     = 0x000080; #  Restore access time on exit 
my \MAGIC_RAW                = 0x000100; #  Don't translate unprintable chars 
my \MAGIC_ERROR              = 0x000200; #  Handle ENOENT etc as real errors 
my \MAGIC_MIME_ENCODING      = 0x000400; #  Return the MIME encoding 
my \MAGIC_MIME               = (MAGIC_MIME_TYPE +| MAGIC_MIME_ENCODING);
my \MAGIC_APPLE              = 0x000800; #  Return the Apple creator and type 
my \MAGIC_NO_CHECK_COMPRESS  = 0x001000; #  Don't check for compressed files 
my \MAGIC_NO_CHECK_TAR       = 0x002000; #  Don't check for tar files 
my \MAGIC_NO_CHECK_SOFT      = 0x004000; #  Don't check magic entries 
my \MAGIC_NO_CHECK_APPTYPE   = 0x008000; #  Don't check application type 
my \MAGIC_NO_CHECK_ELF       = 0x010000; #  Don't check for elf details 
my \MAGIC_NO_CHECK_TEXT      = 0x020000; #  Don't check for text files 
my \MAGIC_NO_CHECK_CDF       = 0x040000; #  Don't check for cdf files 
my \MAGIC_NO_CHECK_TOKENS    = 0x100000; #  Don't check tokens 
my \MAGIC_NO_CHECK_ENCODING  = 0x200000; #  Don't check text encodings 

submethod BUILD (int :$flags = 0, :@!magic-files = ()) {
    $!flags = $flags +^ MAGIC_MIME +^ MAGIC_MIME_TYPE +^ MAGIC_MIME_ENCODING;
    $!cookie = Cookie.new( $!flags, @!magic-files );
    return;
}

method from-filename (Cool $filename, int $flags = 0) returns Hash {
    return self!info-using( 'magic-file', $flags, $filename );
}

method from-handle (IO::Handle $handle, int $flags = 0) returns Hash {
    return self!info-using( 'magic-descriptor', $flags, $handle );
}

method from-buffer (Stringy $buffer, int $flags = 0) returns Hash {
    return self!info-using(
        $buffer ~~ Buf[uint8] ?? 'magic-buffer' !! 'magic-string',
        $flags,
        $buffer,
    );
}

method !info-using(Str $method, int $flags, *@args) returns Hash {
    my $description = $!cookie."$method"( $!flags +| $flags +| MAGIC_NONE,          |@args );
    my $mime-type   = $!cookie."$method"( $!flags +| $flags +| MAGIC_MIME_TYPE,     |@args );
    my $encoding    = $!cookie."$method"( $!flags +| $flags +| MAGIC_MIME_ENCODING, |@args );

    return %(
        description => $description,
        mime-type   => $mime-type,
        encoding    => $encoding,
        mime-type-with-encoding => self!mime-type-with-encoding( $mime-type, $encoding ),
    );
}

method flags-from-args(%flag-args) {
    state %flag-map = (
        debug           => MAGIC_DEBUG,
        follow-symlinks => MAGIC_SYMLINK,
        uncompress      => MAGIC_COMPRESS,
        open-devices    => MAGIC_DEVICES,
        preserve-atime  => MAGIC_PRESERVE_ATIME,
        raw             => MAGIC_RAW,
        apple           => MAGIC_APPLE,
    );

    my $flags = 0;
    for %flag-map.keys -> $k {
        $flags +|= %flag-map{$k} if %flag-args{$k};
    }

    return $!flags +| $flags;
}

method !mime-type-with-encoding ($mime-type, $encoding) returns Str {
    return $mime-type unless $encoding;
    return "$mime-type; charset=$encoding";
}

method magic-version returns int {
    return magic_version();
    # libmagic didn't define magic_version until relatively late, so there are
    # distros out there which don't provide this function.
    CATCH {
        return 0;
    }
}

sub magic_version returns int is native('magic', v1) { * }
