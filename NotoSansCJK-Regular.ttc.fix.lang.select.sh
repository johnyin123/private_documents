cat > /etc/fonts/conf.avail/64-language-selector-prefer.conf <<EOF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
<alias>
<family>sans-serif</family>
<prefer>
<family>Noto Sans CJK SC</family>
<family>Noto Sans CJK TC</family>
<family>Noto Sans CJK JP</family>
</prefer>
</alias>
<!--以上为设置无衬线字体优先度-->
<alias>
<family>monospace</family>
<prefer>
<family>Noto Sans Mono CJK SC</family>
<family>Noto Sans Mono CJK TC</family>
<family>Noto Sans Mono CJK JP</family>
</prefer>
</alias>
<!--以上为设置等宽字体优先度-->
</fontconfig>
EOF

ln -s /etc/fonts/conf.avail/64-language-selector-prefer.conf /etc/fonts/conf.d/64-language-selector-prefer.conf
fc-cache -fv

