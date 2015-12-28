use v6;
use NativeCall;

unit class File::LibMagic;

my class Cookie is repr('CPointer') {
    sub magic_open (int32) returns Cookie is native('magic', v1) { * }

    method new (int32 $flags) returns Cookie {
        return magic_open($flags);
    }

    method DESTROY {
        self.close
    }
    method close (Cookie) is native('magic', v1) { * }

    method magic-descriptor (int32 $flags, IO::Handle $file) returns Str {
        self.setflags($flags);
        return magic_descriptor( self, $file.native-descriptor ); 
    }
    sub magic_descriptor (Cookie, int32) returns Str is native('magic', v1) { * }

    method magic-file (int32 $flags, Str $filename) returns Str {
        self.setflags($flags);
        return magic_file( self, $filename ); 
    }
    sub magic_file (Cookie, Str) returns Str is native('magic', v1) { * }

    method magic-buffer (int32 $flags, Str $buffer) returns Str {
        self.setflags($flags);
        return magic_buffer( self, $buffer, $buffer.encode('UTF-8').elems ); 
    }
    sub magic_buffer (Cookie, Str, int32) returns Str is native('magic', v1) { * }

    sub magic_setflags (Cookie, int32) is native('magic', v1) { * }

    method setflags(int32 $flags) {
        magic_setflags(self, $flags);
    }
}

has Cookie $!cookie;
has int $!flags;

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

submethod BUILD (int :$flags = 0) {
    $!flags = $flags +^ MAGIC_MIME +^ MAGIC_MIME_TYPE +^ MAGIC_MIME_ENCODING;
    $!cookie = Cookie.new($!flags);
    return;
}

method for-filename (Str $filename, int $flags = 0) returns Hash {
    return self!info-using( 'magic-file', $flags, $filename );
}

method for-handle (IO::Handle $handle, int $flags = 0) returns Hash {
    return self!info-using( 'magic-descriptor', $flags, $handle );
}

method for-buffer (Str $buffer, int $flags = 0) returns Hash {
    return self!info-using( 'magic-buffer', $flags, $buffer );
}

method !info-using(Str $method, int $flags, *@args) returns Hash {
    my $description = $!cookie."$method"( $!flags +| MAGIC_MIME,          |@args );
    my $mime-type   = $!cookie."$method"( $!flags +| MAGIC_MIME_TYPE,     |@args );
    my $encoding    = $!cookie."$method"( $!flags +| MAGIC_MIME_ENCODING, |@args );

    return %(
        description => $description,
        mime-type   => $mime-type,
        encoding    => $encoding,
        mime-type-with-encoding => self!mime-type-with-encoding( $mime-type, $encoding ),
    );
}

method !mime-type-with-encoding ($mime-type, $encoding) returns Str {
    return $mime-type unless $encoding;
    return "$mime-type; charset=$encoding";
}

