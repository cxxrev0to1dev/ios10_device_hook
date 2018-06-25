GCC_BIN=`xcrun --sdk iphoneos --find gcc`
SDK=`xcrun --sdk iphoneos --show-sdk-path`
#support iPhone 3GS and above, delete armv6 to avoid SDK error
ARCH_FLAGS=-arch armv7 -arch armv7s -arch arm64

LDFLAGS	=\
	-F$(SDK)/System/Library/Frameworks/\
	-F$(SDK)/System/Library/PrivateFrameworks/\
	-framework UIKit\
	-framework CoreFoundation\
	-framework Foundation\
	-framework CoreGraphics\
	-framework Security\
	-lobjc\
	-lsqlite3\
	-bind_at_load



GCC_ARM = $(GCC_BIN) -Os -DMG_ENABLE_THREADS -Wimplicit -isysroot $(SDK) $(ARCH_FLAGS)

default: iosapps.o list
	@$(GCC_ARM) $(LDFLAGS) iosapps.o -o iosapps

iosapps.o: iosapps.cpp
	$(GCC_ARM) -c iosapps.cpp
clean:
	rm -f *.o

list:
	security find-identity -pcodesigning
	@printf '\nTo codesign, please run: \n\tCER="<40 character hex string for certificate>" make codesign\n'

codesign:
	codesign -fs "$(CER)" --entitlements entitlements.xml iosapps
