#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("9fc7d87[2023-08-16T12:10:14+08:00]:inst_alpine.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
APK=${DIRNAME}/apk.static
APK_TOOLS_URI="https://gitlab.alpinelinux.org/api/v4/projects/5/packages/generic/v2.12.10/x86_64/apk.static"
APK_TOOLS_SHA256="d7506bb11327b337960910daffed75aa289d8bb350feab624c52965be82ceae8"
ALPINE_KEYS='
4a6a0840:MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA1yHJxQgsHQREclQu4Ohe\nqxTxd1tHcNnvnQTu/UrTky8wWvgXT+jpveroeWWnzmsYlDI93eLI2ORakxb3gA2O\nQ0Ry4ws8vhaxLQGC74uQR5+/yYrLuTKydFzuPaS1dK19qJPXB8GMdmFOijnXX4SA\njixuHLe1WW7kZVtjL7nufvpXkWBGjsfrvskdNA/5MfxAeBbqPgaq0QMEfxMAn6/R\nL5kNepi/Vr4S39Xvf2DzWkTLEK8pcnjNkt9/aafhWqFVW7m3HCAII6h/qlQNQKSo\nGuH34Q8GsFG30izUENV9avY7hSLq7nggsvknlNBZtFUcmGoQrtx3FmyYsIC8/R+B\nywIDAQAB
5243ef4b:MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvNijDxJ8kloskKQpJdx+\nmTMVFFUGDoDCbulnhZMJoKNkSuZOzBoFC94omYPtxnIcBdWBGnrm6ncbKRlR+6oy\nDO0W7c44uHKCFGFqBhDasdI4RCYP+fcIX/lyMh6MLbOxqS22TwSLhCVjTyJeeH7K\naA7vqk+QSsF4TGbYzQDDpg7+6aAcNzg6InNePaywA6hbT0JXbxnDWsB+2/LLSF2G\nmnhJlJrWB1WGjkz23ONIWk85W4S0XB/ewDefd4Ly/zyIciastA7Zqnh7p3Ody6Q0\nsS2MJzo7p3os1smGjUF158s6m/JbVh4DN6YIsxwl2OjDOz9R0OycfJSDaBVIGZzg\ncQIDAQAB
524d27bb:MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAr8s1q88XpuJWLCZALdKj\nlN8wg2ePB2T9aIcaxryYE/Jkmtu+ZQ5zKq6BT3y/udt5jAsMrhHTwroOjIsF9DeG\ne8Y3vjz+Hh4L8a7hZDaw8jy3CPag47L7nsZFwQOIo2Cl1SnzUc6/owoyjRU7ab0p\niWG5HK8IfiybRbZxnEbNAfT4R53hyI6z5FhyXGS2Ld8zCoU/R4E1P0CUuXKEN4p0\n64dyeUoOLXEWHjgKiU1mElIQj3k/IF02W89gDj285YgwqA49deLUM7QOd53QLnx+\nxrIrPv3A+eyXMFgexNwCKQU9ZdmWa00MjjHlegSGK8Y2NPnRoXhzqSP9T9i2HiXL\nVQIDAQAB
5261cecb:MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAwlzMkl7b5PBdfMzGdCT0\ncGloRr5xGgVmsdq5EtJvFkFAiN8Ac9MCFy/vAFmS8/7ZaGOXoCDWbYVLTLOO2qtX\nyHRl+7fJVh2N6qrDDFPmdgCi8NaE+3rITWXGrrQ1spJ0B6HIzTDNEjRKnD4xyg4j\ng01FMcJTU6E+V2JBY45CKN9dWr1JDM/nei/Pf0byBJlMp/mSSfjodykmz4Oe13xB\nCa1WTwgFykKYthoLGYrmo+LKIGpMoeEbY1kuUe04UiDe47l6Oggwnl+8XD1MeRWY\nsWgj8sF4dTcSfCMavK4zHRFFQbGp/YFJ/Ww6U9lA3Vq0wyEI6MCMQnoSMFwrbgZw\nwwIDAQAB
58199dcc:MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA3v8/ye/V/t5xf4JiXLXa\nhWFRozsnmn3hobON20GdmkrzKzO/eUqPOKTpg2GtvBhK30fu5oY5uN2ORiv2Y2ht\neLiZ9HVz3XP8Fm9frha60B7KNu66FO5P2o3i+E+DWTPqqPcCG6t4Znk2BypILcit\nwiPKTsgbBQR2qo/cO01eLLdt6oOzAaF94NH0656kvRewdo6HG4urbO46tCAizvCR\nCA7KGFMyad8WdKkTjxh8YLDLoOCtoZmXmQAiwfRe9pKXRH/XXGop8SYptLqyVVQ+\ntegOD9wRs2tOlgcLx4F/uMzHN7uoho6okBPiifRX+Pf38Vx+ozXh056tjmdZkCaV\naQIDAQAB
58cbb476:MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAoSPnuAGKtRIS5fEgYPXD\n8pSGvKAmIv3A08LBViDUe+YwhilSHbYXUEAcSH1KZvOo1WT1x2FNEPBEFEFU1Eyc\n+qGzbA03UFgBNvArurHQ5Z/GngGqE7IarSQFSoqewYRtFSfp+TL9CUNBvM0rT7vz\n2eMu3/wWG+CBmb92lkmyWwC1WSWFKO3x8w+Br2IFWvAZqHRt8oiG5QtYvcZL6jym\nY8T6sgdDlj+Y+wWaLHs9Fc+7vBuyK9C4O1ORdMPW15qVSl4Lc2Wu1QVwRiKnmA+c\nDsH/m7kDNRHM7TjWnuj+nrBOKAHzYquiu5iB3Qmx+0gwnrSVf27Arc3ozUmmJbLj\nzQIDAQAB
58e4f17d:MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvBxJN9ErBgdRcPr5g4hV\nqyUSGZEKuvQliq2Z9SRHLh2J43+EdB6A+yzVvLnzcHVpBJ+BZ9RV30EM9guck9sh\nr+bryZcRHyjG2wiIEoduxF2a8KeWeQH7QlpwGhuobo1+gA8L0AGImiA6UP3LOirl\nI0G2+iaKZowME8/tydww4jx5vG132JCOScMjTalRsYZYJcjFbebQQolpqRaGB4iG\nWqhytWQGWuKiB1A22wjmIYf3t96l1Mp+FmM2URPxD1gk/BIBnX7ew+2gWppXOK9j\n1BJpo0/HaX5XoZ/uMqISAAtgHZAqq+g3IUPouxTphgYQRTRYpz2COw3NF43VYQrR\nbQIDAQAB
60ac2099:MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAwR4uJVtJOnOFGchnMW5Y\nj5/waBdG1u5BTMlH+iQMcV5+VgWhmpZHJCBz3ocD+0IGk2I68S5TDOHec/GSC0lv\n6R9o6F7h429GmgPgVKQsc8mPTPtbjJMuLLs4xKc+viCplXc0Nc0ZoHmCH4da6fCV\ntdpHQjVe6F9zjdquZ4RjV6R6JTiN9v924dGMAkbW/xXmamtz51FzondKC52Gh8Mo\n/oA0/T0KsCMCi7tb4QNQUYrf+Xcha9uus4ww1kWNZyfXJB87a2kORLiWMfs2IBBJ\nTmZ2Fnk0JnHDb8Oknxd9PvJPT0mvyT8DA+KIAPqNvOjUXP4bnjEHJcoCP9S5HkGC\nIQIDAQAB
6165ee59:MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAutQkua2CAig4VFSJ7v54\nALyu/J1WB3oni7qwCZD3veURw7HxpNAj9hR+S5N/pNeZgubQvJWyaPuQDm7PTs1+\ntFGiYNfAsiibX6Rv0wci3M+z2XEVAeR9Vzg6v4qoofDyoTbovn2LztaNEjTkB+oK\ntlvpNhg1zhou0jDVYFniEXvzjckxswHVb8cT0OMTKHALyLPrPOJzVtM9C1ew2Nnc\n3848xLiApMu3NBk0JqfcS3Bo5Y2b1FRVBvdt+2gFoKZix1MnZdAEZ8xQzL/a0YS5\nHd0wj5+EEKHfOd3A75uPa/WQmA+o0cBFfrzm69QDcSJSwGpzWrD1ScH3AK8nWvoj\nv7e9gukK/9yl1b4fQQ00vttwJPSgm9EnfPHLAtgXkRloI27H6/PuLoNvSAMQwuCD\nhQRlyGLPBETKkHeodfLoULjhDi1K2gKJTMhtbnUcAA7nEphkMhPWkBpgFdrH+5z4\nLxy+3ek0cqcI7K68EtrffU8jtUj9LFTUC8dERaIBs7NgQ/LfDbDfGh9g6qVj1hZl\nk9aaIPTm/xsi8v3u+0qaq7KzIBc9s59JOoA8TlpOaYdVgSQhHHLBaahOuAigH+VI\nisbC9vmqsThF2QdDtQt37keuqoda2E6sL7PUvIyVXDRfwX7uMDjlzTxHTymvq2Ck\nhtBqojBnThmjJQFgZXocHG8CAwEAAQ==
61666e3f:MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAlEyxkHggKCXC2Wf5Mzx4\nnZLFZvU2bgcA3exfNPO/g1YunKfQY+Jg4fr6tJUUTZ3XZUrhmLNWvpvSwDS19ZmC\nIXOu0+V94aNgnhMsk9rr59I8qcbsQGIBoHzuAl8NzZCgdbEXkiY90w1skUw8J57z\nqCsMBydAueMXuWqF5nGtYbi5vHwK42PffpiZ7G5Kjwn8nYMW5IZdL6ZnMEVJUWC9\nI4waeKg0yskczYDmZUEAtrn3laX9677ToCpiKrvmZYjlGl0BaGp3cxggP2xaDbUq\nqfFxWNgvUAb3pXD09JM6Mt6HSIJaFc9vQbrKB9KT515y763j5CC2KUsilszKi3mB\nHYe5PoebdjS7D1Oh+tRqfegU2IImzSwW3iwA7PJvefFuc/kNIijfS/gH/cAqAK6z\nbhdOtE/zc7TtqW2Wn5Y03jIZdtm12CxSxwgtCF1NPyEWyIxAQUX9ACb3M0FAZ61n\nfpPrvwTaIIxxZ01L3IzPLpbc44x/DhJIEU+iDt6IMTrHOphD9MCG4631eIdB0H1b\n6zbNX1CXTsafqHRFV9XmYYIeOMggmd90s3xIbEujA6HKNP/gwzO6CDJ+nHFDEqoF\nSkxRdTkEqjTjVKieURW7Swv7zpfu5PrsrrkyGnsRrBJJzXlm2FOOxnbI2iSL1B5F\nrO5kbUxFeZUIDq+7Yv4kLWcCAwEAAQ==
616a9724:MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAnC+bR4bHf/L6QdU4puhQ\ngl1MHePszRC38bzvVFDUJsmCaMCL2suCs2A2yxAgGb9pu9AJYLAmxQC4mM3jNqhg\n/E7yuaBbek3O02zN/ctvflJ250wZCy+z0ZGIp1ak6pu1j14IwHokl9j36zNfGtfv\nADVOcdpWITFFlPqwq1qt/H3UsKVmtiF3BNWWTeUEQwKvlU8ymxgS99yn0+4OPyNT\nL3EUeS+NQJtDS01unau0t7LnjUXn+XIneWny8bIYOQCuVR6s/gpIGuhBaUqwaJOw\n7jkJZYF2Ij7uPb4b5/R3vX2FfxxqEHqssFSg8FFUNTZz3qNZs0CRVyfA972g9WkJ\nhPfn31pQYil4QGRibCMIeU27YAEjXoqfJKEPh4UWMQsQLrEfdGfb8VgwrPbniGfU\nL3jKJR3VAafL9330iawzVQDlIlwGl6u77gEXMl9K0pfazunYhAp+BMP+9ot5ckK+\nosmrqj11qMESsAj083GeFdfV3pXEIwUytaB0AKEht9DbqUfiE/oeZ/LAXgySMtVC\nsbC4ESmgVeY2xSBIJdDyUap7FR49GGrw0W49NUv9gRgQtGGaNVQQO9oGL2PBC41P\niWF9GLoX30HIz1P8PF/cZvicSSPkQf2Z6TV+t0ebdGNS5DjapdnCrq8m9Z0pyKsQ\nuxAL2a7zX8l5i1CZh1ycUGsCAwEAAQ==
616abc23:MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA0MfCDrhODRCIxR9Dep1s\neXafh5CE5BrF4WbCgCsevyPIdvTeyIaW4vmO3bbG4VzhogDZju+R3IQYFuhoXP5v\nY+zYJGnwrgz3r5wYAvPnLEs1+dtDKYOgJXQj+wLJBW1mzRDL8FoRXOe5iRmn1EFS\nwZ1DoUvyu7/J5r0itKicZp3QKED6YoilXed+1vnS4Sk0mzN4smuMR9eO1mMCqNp9\n9KTfRDHTbakIHwasECCXCp50uXdoW6ig/xUAFanpm9LtK6jctNDbXDhQmgvAaLXZ\nLvFqoaYJ/CvWkyYCgL6qxvMvVmPoRv7OPcyni4xR/WgWa0MSaEWjgPx3+yj9fiMA\n1S02pFWFDOr5OUF/O4YhFJvUCOtVsUPPfA/Lj6faL0h5QI9mQhy5Zb9TTaS9jB6p\nLw7u0dJlrjFedk8KTJdFCcaGYHP6kNPnOxMylcB/5WcztXZVQD5WpCicGNBxCGMm\nW64SgrV7M07gQfL/32QLsdqPUf0i8hoVD8wfQ3EpbQzv6Fk1Cn90bZqZafg8XWGY\nwddhkXk7egrr23Djv37V2okjzdqoyLBYBxMz63qQzFoAVv5VoY2NDTbXYUYytOvG\nGJ1afYDRVWrExCech1mX5ZVUB1br6WM+psFLJFoBFl6mDmiYt0vMYBddKISsvwLl\nIJQkzDwtXzT2cSjoj3T5QekCAwEAAQ==
616ac3bc:MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAvaaoSLab+IluixwKV5Od\n0gib2YurjPatGIbn5Ov2DLUFYiebj2oJINXJSwUOO+4WcuHFEqiL/1rya+k5hLZt\nhnPL1tn6QD4rESznvGSasRCQNT2vS/oyZbTYJRyAtFkEYLlq0t3S3xBxxHWuvIf0\nqVxVNYpQWyM3N9RIeYBR/euXKJXileSHk/uq1I5wTC0XBIHWcthczGN0m9wBEiWS\n0m3cnPk4q0Ea8mUJ91Rqob19qETz6VbSPYYpZk3qOycjKosuwcuzoMpwU8KRiMFd\n5LHtX0Hx85ghGsWDVtS0c0+aJa4lOMGvJCAOvDfqvODv7gKlCXUpgumGpLdTmaZ8\n1RwqspAe3IqBcdKTqRD4m2mSg23nVx2FAY3cjFvZQtfooT7q1ItRV5RgH6FhQSl7\n+6YIMJ1Bf8AAlLdRLpg+doOUGcEn+pkDiHFgI8ylH1LKyFKw+eXaAml/7DaWZk1d\ndqggwhXOhc/UUZFQuQQ8A8zpA13PcbC05XxN2hyP93tCEtyynMLVPtrRwDnHxFKa\nqKzs3rMDXPSXRn3ZZTdKH3069ApkEjQdpcwUh+EmJ1Ve/5cdtzT6kKWCjKBFZP/s\n91MlRrX2BTRdHaU5QJkUheUtakwxuHrdah2F94lRmsnQlpPr2YseJu6sIE+Dnx4M\nCfhdVbQL2w54R645nlnohu8CAwEAAQ==
616adfeb:MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAq0BFD1D4lIxQcsqEpQzU\npNCYM3aP1V/fxxVdT4DWvSI53JHTwHQamKdMWtEXetWVbP5zSROniYKFXd/xrD9X\n0jiGHey3lEtylXRIPxe5s+wXoCmNLcJVnvTcDtwx/ne2NLHxp76lyc25At+6RgE6\nADjLVuoD7M4IFDkAsd8UQ8zM0Dww9SylIk/wgV3ZkifecvgUQRagrNUdUjR56EBZ\nraQrev4hhzOgwelT0kXCu3snbUuNY/lU53CoTzfBJ5UfEJ5pMw1ij6X0r5S9IVsy\nKLWH1hiO0NzU2c8ViUYCly4Fe9xMTFc6u2dy/dxf6FwERfGzETQxqZvSfrRX+GLj\n/QZAXiPg5178hT/m0Y3z5IGenIC/80Z9NCi+byF1WuJlzKjDcF/TU72zk0+PNM/H\nKuppf3JT4DyjiVzNC5YoWJT2QRMS9KLP5iKCSThwVceEEg5HfhQBRT9M6KIcFLSs\nmFjx9kNEEmc1E8hl5IR3+3Ry8G5/bTIIruz14jgeY9u5jhL8Vyyvo41jgt9sLHR1\n/J1TxKfkgksYev7PoX6/ZzJ1ksWKZY5NFoDXTNYUgzFUTOoEaOg3BAQKadb3Qbbq\nXIrxmPBdgrn9QI7NCgfnAY3Tb4EEjs3ON/BNyEhUENcXOH6I1NbcuBQ7g9P73kE4\nVORdoc8MdJ5eoKBpO8Ww8HECAwEAAQ==
616ae350:MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAyduVzi1mWm+lYo2Tqt/0\nXkCIWrDNP1QBMVPrE0/ZlU2bCGSoo2Z9FHQKz/mTyMRlhNqTfhJ5qU3U9XlyGOPJ\npiM+b91g26pnpXJ2Q2kOypSgOMOPA4cQ42PkHBEqhuzssfj9t7x47ppS94bboh46\nxLSDRff/NAbtwTpvhStV3URYkxFG++cKGGa5MPXBrxIp+iZf9GnuxVdST5PGiVGP\nODL/b69sPJQNbJHVquqUTOh5Ry8uuD2WZuXfKf7/C0jC/ie9m2+0CttNu9tMciGM\nEyKG1/Xhk5iIWO43m4SrrT2WkFlcZ1z2JSf9Pjm4C2+HovYpihwwdM/OdP8Xmsnr\nDzVB4YvQiW+IHBjStHVuyiZWc+JsgEPJzisNY0Wyc/kNyNtqVKpX6dRhMLanLmy+\nf53cCSI05KPQAcGj6tdL+D60uKDkt+FsDa0BTAobZ31OsFVid0vCXtsbplNhW1IF\nHwsGXBTVcfXg44RLyL8Lk/2dQxDHNHzAUslJXzPxaHBLmt++2COa2EI1iWlvtznk\nOk9WP8SOAIj+xdqoiHcC4j72BOVVgiITIJNHrbppZCq6qPR+fgXmXa+sDcGh30m6\n9Wpbr28kLMSHiENCWTdsFij+NQTd5S47H7XTROHnalYDuF1RpS+DpQidT5tUimaT\nJZDr++FjKrnnijbyNF8b98UCAwEAAQ==
616db30d:MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAnpUpyWDWjlUk3smlWeA0\nlIMW+oJ38t92CRLHH3IqRhyECBRW0d0aRGtq7TY8PmxjjvBZrxTNDpJT6KUk4LRm\na6A6IuAI7QnNK8SJqM0DLzlpygd7GJf8ZL9SoHSH+gFsYF67Cpooz/YDqWrlN7Vw\ntO00s0B+eXy+PCXYU7VSfuWFGK8TGEv6HfGMALLjhqMManyvfp8hz3ubN1rK3c8C\nUS/ilRh1qckdbtPvoDPhSbTDmfU1g/EfRSIEXBrIMLg9ka/XB9PvWRrekrppnQzP\nhP9YE3x/wbFc5QqQWiRCYyQl/rgIMOXvIxhkfe8H5n1Et4VAorkpEAXdsfN8KSVv\nLSMazVlLp9GYq5SUpqYX3KnxdWBgN7BJoZ4sltsTpHQ/34SXWfu3UmyUveWj7wp0\nx9hwsPirVI00EEea9AbP7NM2rAyu6ukcm4m6ATd2DZJIViq2es6m60AE6SMCmrQF\nwmk4H/kdQgeAELVfGOm2VyJ3z69fQuywz7xu27S6zTKi05Qlnohxol4wVb6OB7qG\nLPRtK9ObgzRo/OPumyXqlzAi/Yvyd1ZQk8labZps3e16bQp8+pVPiumWioMFJDWV\nGZjCmyMSU8V6MB6njbgLHoyg2LCukCAeSjbPGGGYhnKLm1AKSoJh3IpZuqcKCk5C\n8CM1S15HxV78s9dFntEqIokCAwEAAQ==
'
dump_alpine_keys() {
	local dest_dir="$1"
	local content="" id="" line=""
	mkdir -p "$dest_dir"
	for line in $ALPINE_KEYS; do
		id=${line%%:*}
		content=${line#*:}
		printf -- "-----BEGIN PUBLIC KEY-----\n$content\n-----END PUBLIC KEY-----\n" \
			> "$dest_dir/alpine-devel@lists.alpinelinux.org-$id.rsa.pub"
	done
}
main() {
    arch="" alpine_mirror="http://192.168.168.1/alpine" branch="latest-stable"
    alpine_packages="build-base ca-certificates ssl_client"
    chroot_dir="${DIRNAME}"/alpine
    temp_dir=$(mktemp -d || echo /tmp/alpine)
    mkdir -p "${chroot_dir}"/etc/apk/keys
    cat <<EOF > "${chroot_dir}"/etc/apk/repositories
${alpine_mirror}/${branch}/main
${alpine_mirror}/${branch}/community
EOF
    dump_alpine_keys "${chroot_dir}"/etc/apk/keys/
    cp /etc/resolv.conf "${chroot_dir}"/etc/resolv.conf
    "$APK" add --root "${chroot_dir}" --update-cache --initdb --no-progress ${arch:+--arch $arch} \
	    alpine-baselayout apk-tools busybox busybox-suid musl-utils
    if "$APK" info --root "${chroot_dir}" --no-progress --quiet alpine-release >/dev/null; then
	    "$APK" add --root "${chroot_dir}" --no-progress alpine-release
    else
	    # In Alpine <3.17, this package contains /etc/os-release,
	    # /etc/alpine-release and /etc/issue, but we don't wanna install all
	    # its dependencies (e.g. openrc).
	    "$APK" fetch --root "${chroot_dir}" --no-progress --stdout alpine-base | tar -xz etc
    fi
    LC_ALL=C LANGUAGE=C LANG=C chroot "${chroot_dir}" /bin/sh <<'EOFSHELL'
    apk add grub grub-bios grub-efi
    ecoh "Modify grub/cmdline--------------------"
    sed --quiet -i.orig -E \
        -e '/^\s*(GRUB_CMDLINE_LINUX).*/!p' \
        -e '$aGRUB_CMDLINE_LINUX=modules=xfs,ext4' \
        /etc/default/grub
    source /etc/mkinitfs/mkinitfs.conf
    echo "features=\"${features} xfs\"" > /etc/mkinitfs/mkinitfs.conf
    apk add linux-lts xfsprogs e2fsprogs linux-firmware-none openssh-server bridge-utils
    echo "SSHD ...."
    sed --quiet -i.orig -E \
        -e '/^\s*(UseDNS|MaxAuthTries|GSSAPIAuthentication|Port|Ciphers|MACs|PermitRootLogin).*/!p' \
        -e '$aUseDNS no' \
        -e '$aMaxAuthTries 3' \
        -e '$aGSSAPIAuthentication no' \
        -e '$aPort 60022' \
        -e '$aCiphers aes256-ctr,aes192-ctr,aes128-ctr' \
        -e '$aMACs hmac-sha1' \
        -e '$aPermitRootLogin without-password' \
        /etc/ssh/sshd_config
    [ ! -d /root/.ssh ] && mkdir -m0700 /root/.ssh
    cat <<EOF >/root/.ssh/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDKxdriiCqbzlKWZgW5JGF6yJnSyVtubEAW17mok2zsQ7al2cRYgGjJ5iFSvZHzz3at7QpNpRkafauH/DfrZz3yGKkUIbOb0UavCH5aelNduXaBt7dY2ORHibOsSvTXAifGwtLY67W4VyU/RBnCC7x3HxUB6BQF6qwzCGwry/lrBD6FZzt7tLjfxcbLhsnzqOG2y76n4H54RrooGn1iXHBDBXfvMR7noZKbzXAUQyOx9m07CqhnpgpMlGFL7shUdlFPNLPZf5JLsEs90h3d885OWRx9Kp+O05W2gPg4kUhGeqO6IY09EPOcTupw77PRHoWOg4xNcqEQN2v2C1lr09Y9 root@yinzh
EOF
    chmod 0600 /root/.ssh/authorized_keys
EOFSHELL
    cat <<EOF> ${chroot_dir}/etc/network/interfaces
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
	address 192.168.168.102
	netmask 255.255.255.0
	gateway 192.168.168.1
EOF

    chroot ${chroot_dir} /usr/bin/env -i PS1='\u@pcsrv:\w$' /bin/sh --noprofile --norc -o vi || true
cat<<'EOF'
apk add grub grub-bios grub-efi linux-lts xfsprogs
echo GRUB_CMDLINE_LINUX=modules=xfs,ext4 >> /etc/default/grub
source /etc/mkinitfs/mkinitfs.conf
echo "features=\"${features} xfs\"" > /etc/mkinitfs/mkinitfs.conf
EOF
}
main "$@"
