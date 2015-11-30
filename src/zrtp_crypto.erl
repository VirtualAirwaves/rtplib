%%%----------------------------------------------------------------------
%%% Copyright (c) 2012 Peter Lemenkov <lemenkov@gmail.com>
%%%
%%% All rights reserved.
%%%
%%% Redistribution and use in source and binary forms, with or without modification,
%%% are permitted provided that the following conditions are met:
%%%
%%% * Redistributions of source code must retain the above copyright notice, this
%%% list of conditions and the following disclaimer.
%%% * Redistributions in binary form must reproduce the above copyright notice,
%%% this list of conditions and the following disclaimer in the documentation
%%% and/or other materials provided with the distribution.
%%% * Neither the name of the authors nor the names of its contributors
%%% may be used to endorse or promote products derived from this software
%%% without specific prior written permission.
%%%
%%% THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ''AS IS'' AND ANY
%%% EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
%%% WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
%%% DISCLAIMED. IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE FOR ANY
%%% DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
%%% (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
%%% LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
%%% ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
%%% (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
%%% SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
%%%
%%%----------------------------------------------------------------------

-module(zrtp_crypto).

-export([mkdh/1]).
-export([mkfinal/2]).
-export([kdf/4]).
-export([sas/2]).
-export([get_hashfun/1]).
-export([get_hmacfun/1]).
-export([get_hashlength/1]).
-export([get_keylength/1]).
-export([get_taglength/1]).

-export([mkhmac/2]).
-export([verify_hmac/3]).

-include("../include/zrtp.hrl").

%% 256 bytes
ret_P2048() ->
	P2048 = <<16#FF, 16#FF, 16#FF, 16#FF, 16#FF, 16#FF, 16#FF, 16#FF, 16#C9, 16#0F, 16#DA, 16#A2,
	16#21, 16#68, 16#C2, 16#34, 16#C4, 16#C6, 16#62, 16#8B, 16#80, 16#DC, 16#1C, 16#D1,
	16#29, 16#02, 16#4E, 16#08, 16#8A, 16#67, 16#CC, 16#74, 16#02, 16#0B, 16#BE, 16#A6,
	16#3B, 16#13, 16#9B, 16#22, 16#51, 16#4A, 16#08, 16#79, 16#8E, 16#34, 16#04, 16#DD,
	16#EF, 16#95, 16#19, 16#B3, 16#CD, 16#3A, 16#43, 16#1B, 16#30, 16#2B, 16#0A, 16#6D,
	16#F2, 16#5F, 16#14, 16#37, 16#4F, 16#E1, 16#35, 16#6D, 16#6D, 16#51, 16#C2, 16#45,
	16#E4, 16#85, 16#B5, 16#76, 16#62, 16#5E, 16#7E, 16#C6, 16#F4, 16#4C, 16#42, 16#E9,
	16#A6, 16#37, 16#ED, 16#6B, 16#0B, 16#FF, 16#5C, 16#B6, 16#F4, 16#06, 16#B7, 16#ED,
	16#EE, 16#38, 16#6B, 16#FB, 16#5A, 16#89, 16#9F, 16#A5, 16#AE, 16#9F, 16#24, 16#11,
	16#7C, 16#4B, 16#1F, 16#E6, 16#49, 16#28, 16#66, 16#51, 16#EC, 16#E4, 16#5B, 16#3D,
	16#C2, 16#00, 16#7C, 16#B8, 16#A1, 16#63, 16#BF, 16#05, 16#98, 16#DA, 16#48, 16#36,
	16#1C, 16#55, 16#D3, 16#9A, 16#69, 16#16, 16#3F, 16#A8, 16#FD, 16#24, 16#CF, 16#5F,
	16#83, 16#65, 16#5D, 16#23, 16#DC, 16#A3, 16#AD, 16#96, 16#1C, 16#62, 16#F3, 16#56,
	16#20, 16#85, 16#52, 16#BB, 16#9E, 16#D5, 16#29, 16#07, 16#70, 16#96, 16#96, 16#6D,
	16#67, 16#0C, 16#35, 16#4E, 16#4A, 16#BC, 16#98, 16#04, 16#F1, 16#74, 16#6C, 16#08,
	16#CA, 16#18, 16#21, 16#7C, 16#32, 16#90, 16#5E, 16#46, 16#2E, 16#36, 16#CE, 16#3B,
	16#E3, 16#9E, 16#77, 16#2C, 16#18, 16#0E, 16#86, 16#03, 16#9B, 16#27, 16#83, 16#A2,
	16#EC, 16#07, 16#A2, 16#8F, 16#B5, 16#C5, 16#5D, 16#F0, 16#6F, 16#4C, 16#52, 16#C9,
	16#DE, 16#2B, 16#CB, 16#F6, 16#95, 16#58, 16#17, 16#18, 16#39, 16#95, 16#49, 16#7C,
	16#EA, 16#95, 16#6A, 16#E5, 16#15, 16#D2, 16#26, 16#18, 16#98, 16#FA, 16#05, 16#10,
	16#15, 16#72, 16#8E, 16#5A, 16#8A, 16#AC, 16#AA, 16#68, 16#FF, 16#FF, 16#FF, 16#FF,
	16#FF, 16#FF, 16#FF, 16#FF>>,
	<<256:32/integer-big, P2048/binary>>.

%% 384 bytes
ret_P3072() ->
	P3072 = <<16#FF, 16#FF, 16#FF, 16#FF, 16#FF, 16#FF, 16#FF, 16#FF, 16#C9, 16#0F, 16#DA, 16#A2,
	16#21, 16#68, 16#C2, 16#34, 16#C4, 16#C6, 16#62, 16#8B, 16#80, 16#DC, 16#1C, 16#D1,
	16#29, 16#02, 16#4E, 16#08, 16#8A, 16#67, 16#CC, 16#74, 16#02, 16#0B, 16#BE, 16#A6,
	16#3B, 16#13, 16#9B, 16#22, 16#51, 16#4A, 16#08, 16#79, 16#8E, 16#34, 16#04, 16#DD,
	16#EF, 16#95, 16#19, 16#B3, 16#CD, 16#3A, 16#43, 16#1B, 16#30, 16#2B, 16#0A, 16#6D,
	16#F2, 16#5F, 16#14, 16#37, 16#4F, 16#E1, 16#35, 16#6D, 16#6D, 16#51, 16#C2, 16#45,
	16#E4, 16#85, 16#B5, 16#76, 16#62, 16#5E, 16#7E, 16#C6, 16#F4, 16#4C, 16#42, 16#E9,
	16#A6, 16#37, 16#ED, 16#6B, 16#0B, 16#FF, 16#5C, 16#B6, 16#F4, 16#06, 16#B7, 16#ED,
	16#EE, 16#38, 16#6B, 16#FB, 16#5A, 16#89, 16#9F, 16#A5, 16#AE, 16#9F, 16#24, 16#11,
	16#7C, 16#4B, 16#1F, 16#E6, 16#49, 16#28, 16#66, 16#51, 16#EC, 16#E4, 16#5B, 16#3D,
	16#C2, 16#00, 16#7C, 16#B8, 16#A1, 16#63, 16#BF, 16#05, 16#98, 16#DA, 16#48, 16#36,
	16#1C, 16#55, 16#D3, 16#9A, 16#69, 16#16, 16#3F, 16#A8, 16#FD, 16#24, 16#CF, 16#5F,
	16#83, 16#65, 16#5D, 16#23, 16#DC, 16#A3, 16#AD, 16#96, 16#1C, 16#62, 16#F3, 16#56,
	16#20, 16#85, 16#52, 16#BB, 16#9E, 16#D5, 16#29, 16#07, 16#70, 16#96, 16#96, 16#6D,
	16#67, 16#0C, 16#35, 16#4E, 16#4A, 16#BC, 16#98, 16#04, 16#F1, 16#74, 16#6C, 16#08,
	16#CA, 16#18, 16#21, 16#7C, 16#32, 16#90, 16#5E, 16#46, 16#2E, 16#36, 16#CE, 16#3B,
	16#E3, 16#9E, 16#77, 16#2C, 16#18, 16#0E, 16#86, 16#03, 16#9B, 16#27, 16#83, 16#A2,
	16#EC, 16#07, 16#A2, 16#8F, 16#B5, 16#C5, 16#5D, 16#F0, 16#6F, 16#4C, 16#52, 16#C9,
	16#DE, 16#2B, 16#CB, 16#F6, 16#95, 16#58, 16#17, 16#18, 16#39, 16#95, 16#49, 16#7C,
	16#EA, 16#95, 16#6A, 16#E5, 16#15, 16#D2, 16#26, 16#18, 16#98, 16#FA, 16#05, 16#10,
	16#15, 16#72, 16#8E, 16#5A, 16#8A, 16#AA, 16#C4, 16#2D, 16#AD, 16#33, 16#17, 16#0D,
	16#04, 16#50, 16#7A, 16#33, 16#A8, 16#55, 16#21, 16#AB, 16#DF, 16#1C, 16#BA, 16#64,
	16#EC, 16#FB, 16#85, 16#04, 16#58, 16#DB, 16#EF, 16#0A, 16#8A, 16#EA, 16#71, 16#57,
	16#5D, 16#06, 16#0C, 16#7D, 16#B3, 16#97, 16#0F, 16#85, 16#A6, 16#E1, 16#E4, 16#C7,
	16#AB, 16#F5, 16#AE, 16#8C, 16#DB, 16#09, 16#33, 16#D7, 16#1E, 16#8C, 16#94, 16#E0,
	16#4A, 16#25, 16#61, 16#9D, 16#CE, 16#E3, 16#D2, 16#26, 16#1A, 16#D2, 16#EE, 16#6B,
	16#F1, 16#2F, 16#FA, 16#06, 16#D9, 16#8A, 16#08, 16#64, 16#D8, 16#76, 16#02, 16#73,
	16#3E, 16#C8, 16#6A, 16#64, 16#52, 16#1F, 16#2B, 16#18, 16#17, 16#7B, 16#20, 16#0C,
	16#BB, 16#E1, 16#17, 16#57, 16#7A, 16#61, 16#5D, 16#6C, 16#77, 16#09, 16#88, 16#C0,
	16#BA, 16#D9, 16#46, 16#E2, 16#08, 16#E2, 16#4F, 16#A0, 16#74, 16#E5, 16#AB, 16#31,
	16#43, 16#DB, 16#5B, 16#FC, 16#E0, 16#FD, 16#10, 16#8E, 16#4B, 16#82, 16#D1, 16#20,
	16#A9, 16#3A, 16#D2, 16#CA, 16#FF, 16#FF, 16#FF, 16#FF, 16#FF, 16#FF, 16#FF, 16#FF>>,
	<<384:32/integer-big, P3072/binary>>.

%% 512 bytes
ret_P4096() ->
	P4096 =	<<16#FF, 16#FF, 16#FF, 16#FF, 16#FF, 16#FF, 16#FF, 16#FF, 16#C9, 16#0F, 16#DA, 16#A2,
	16#21, 16#68, 16#C2, 16#34, 16#C4, 16#C6, 16#62, 16#8B, 16#80, 16#DC, 16#1C, 16#D1,
	16#29, 16#02, 16#4E, 16#08, 16#8A, 16#67, 16#CC, 16#74, 16#02, 16#0B, 16#BE, 16#A6,
	16#3B, 16#13, 16#9B, 16#22, 16#51, 16#4A, 16#08, 16#79, 16#8E, 16#34, 16#04, 16#DD,
	16#EF, 16#95, 16#19, 16#B3, 16#CD, 16#3A, 16#43, 16#1B, 16#30, 16#2B, 16#0A, 16#6D,
	16#F2, 16#5F, 16#14, 16#37, 16#4F, 16#E1, 16#35, 16#6D, 16#6D, 16#51, 16#C2, 16#45,
	16#E4, 16#85, 16#B5, 16#76, 16#62, 16#5E, 16#7E, 16#C6, 16#F4, 16#4C, 16#42, 16#E9,
	16#A6, 16#37, 16#ED, 16#6B, 16#0B, 16#FF, 16#5C, 16#B6, 16#F4, 16#06, 16#B7, 16#ED,
	16#EE, 16#38, 16#6B, 16#FB, 16#5A, 16#89, 16#9F, 16#A5, 16#AE, 16#9F, 16#24, 16#11,
	16#7C, 16#4B, 16#1F, 16#E6, 16#49, 16#28, 16#66, 16#51, 16#EC, 16#E4, 16#5B, 16#3D,
	16#C2, 16#00, 16#7C, 16#B8, 16#A1, 16#63, 16#BF, 16#05, 16#98, 16#DA, 16#48, 16#36,
	16#1C, 16#55, 16#D3, 16#9A, 16#69, 16#16, 16#3F, 16#A8, 16#FD, 16#24, 16#CF, 16#5F,
	16#83, 16#65, 16#5D, 16#23, 16#DC, 16#A3, 16#AD, 16#96, 16#1C, 16#62, 16#F3, 16#56,
	16#20, 16#85, 16#52, 16#BB, 16#9E, 16#D5, 16#29, 16#07, 16#70, 16#96, 16#96, 16#6D,
	16#67, 16#0C, 16#35, 16#4E, 16#4A, 16#BC, 16#98, 16#04, 16#F1, 16#74, 16#6C, 16#08,
	16#CA, 16#18, 16#21, 16#7C, 16#32, 16#90, 16#5E, 16#46, 16#2E, 16#36, 16#CE, 16#3B,
	16#E3, 16#9E, 16#77, 16#2C, 16#18, 16#0E, 16#86, 16#03, 16#9B, 16#27, 16#83, 16#A2,
	16#EC, 16#07, 16#A2, 16#8F, 16#B5, 16#C5, 16#5D, 16#F0, 16#6F, 16#4C, 16#52, 16#C9,
	16#DE, 16#2B, 16#CB, 16#F6, 16#95, 16#58, 16#17, 16#18, 16#39, 16#95, 16#49, 16#7C,
	16#EA, 16#95, 16#6A, 16#E5, 16#15, 16#D2, 16#26, 16#18, 16#98, 16#FA, 16#05, 16#10,
	16#15, 16#72, 16#8E, 16#5A, 16#8A, 16#AA, 16#C4, 16#2D, 16#AD, 16#33, 16#17, 16#0D,
	16#04, 16#50, 16#7A, 16#33, 16#A8, 16#55, 16#21, 16#AB, 16#DF, 16#1C, 16#BA, 16#64,
	16#EC, 16#FB, 16#85, 16#04, 16#58, 16#DB, 16#EF, 16#0A, 16#8A, 16#EA, 16#71, 16#57,
	16#5D, 16#06, 16#0C, 16#7D, 16#B3, 16#97, 16#0F, 16#85, 16#A6, 16#E1, 16#E4, 16#C7,
	16#AB, 16#F5, 16#AE, 16#8C, 16#DB, 16#09, 16#33, 16#D7, 16#1E, 16#8C, 16#94, 16#E0,
	16#4A, 16#25, 16#61, 16#9D, 16#CE, 16#E3, 16#D2, 16#26, 16#1A, 16#D2, 16#EE, 16#6B,
	16#F1, 16#2F, 16#FA, 16#06, 16#D9, 16#8A, 16#08, 16#64, 16#D8, 16#76, 16#02, 16#73,
	16#3E, 16#C8, 16#6A, 16#64, 16#52, 16#1F, 16#2B, 16#18, 16#17, 16#7B, 16#20, 16#0C,
	16#BB, 16#E1, 16#17, 16#57, 16#7A, 16#61, 16#5D, 16#6C, 16#77, 16#09, 16#88, 16#C0,
	16#BA, 16#D9, 16#46, 16#E2, 16#08, 16#E2, 16#4F, 16#A0, 16#74, 16#E5, 16#AB, 16#31,
	16#43, 16#DB, 16#5B, 16#FC, 16#E0, 16#FD, 16#10, 16#8E, 16#4B, 16#82, 16#D1, 16#20,
	16#A9, 16#21, 16#08, 16#01, 16#1A, 16#72, 16#3C, 16#12, 16#A7, 16#87, 16#E6, 16#D7,
	16#88, 16#71, 16#9A, 16#10, 16#BD, 16#BA, 16#5B, 16#26, 16#99, 16#C3, 16#27, 16#18,
	16#6A, 16#F4, 16#E2, 16#3C, 16#1A, 16#94, 16#68, 16#34, 16#B6, 16#15, 16#0B, 16#DA,
	16#25, 16#83, 16#E9, 16#CA, 16#2A, 16#D4, 16#4C, 16#E8, 16#DB, 16#BB, 16#C2, 16#DB,
	16#04, 16#DE, 16#8E, 16#F9, 16#2E, 16#8E, 16#FC, 16#14, 16#1F, 16#BE, 16#CA, 16#A6,
	16#28, 16#7C, 16#59, 16#47, 16#4E, 16#6B, 16#C0, 16#5D, 16#99, 16#B2, 16#96, 16#4F,
	16#A0, 16#90, 16#C3, 16#A2, 16#23, 16#3B, 16#A1, 16#86, 16#51, 16#5B, 16#E7, 16#ED,
	16#1F, 16#61, 16#29, 16#70, 16#CE, 16#E2, 16#D7, 16#AF, 16#B8, 16#1B, 16#DD, 16#76,
	16#21, 16#70, 16#48, 16#1C, 16#D0, 16#06, 16#91, 16#27, 16#D5, 16#B0, 16#5A, 16#A9,
	16#93, 16#B4, 16#EA, 16#98, 16#8D, 16#8F, 16#DD, 16#C1, 16#86, 16#FF, 16#B7, 16#DC,
	16#90, 16#A6, 16#C0, 16#8F, 16#4D, 16#F4, 16#35, 16#C9, 16#34, 16#06, 16#31, 16#99,
	16#FF, 16#FF, 16#FF, 16#FF, 16#FF, 16#FF, 16#FF, 16#FF>>,
	<<512:32/integer-big, P4096/binary>>.


mkdh(KeyAgr) ->
	P = case KeyAgr of
		?ZRTP_KEY_AGREEMENT_DH2K -> ret_P2048();
		?ZRTP_KEY_AGREEMENT_DH3K -> ret_P3072();
		?ZRTP_KEY_AGREEMENT_DH4K -> ret_P4096()
	end,
	G = crypto:mpint(2),
	crypto:dh_generate_key([P, G]).

mkfinal(Pvr, PrivateKey) ->
	G = crypto:mpint(2),
	case size(Pvr) of
		256 ->
			P = ret_P2048(),
			crypto:dh_compute_key(<<256:32/integer-big, Pvr/binary>>, PrivateKey, [P, G]);
		384 ->
			P = ret_P3072(),
			crypto:dh_compute_key(<<384:32/integer-big, Pvr/binary>>, PrivateKey, [P, G]);
		512 ->
			P = ret_P4096(),
			crypto:dh_compute_key(<<512:32/integer-big, Pvr/binary>>, PrivateKey, [P, G])
	end.

kdf(?ZRTP_HASH_S256, Key, Label, KDF_Context) ->
	crypto:hmac(sha256, Key, <<1:32, Label/binary, 0:32, KDF_Context/binary, 256:8>>);
kdf(?ZRTP_HASH_S384, Key, Label, KDF_Context) ->
	crypto:hmac(sha384, Key, <<1:32, Label/binary, 0:32, KDF_Context/binary, 384:8>>).

sas(SASValue, ?ZRTP_SAS_TYPE_B32) ->
	sas:b32(SASValue);
sas(SASValue, ?ZRTP_SAS_TYPE_B256) ->
	sas:b256(SASValue).

get_hashfun(?ZRTP_HASH_S256) -> fun(Data) -> crypto:hash(sha256, Data) end;
get_hashfun(?ZRTP_HASH_S384) -> fun(Data) -> crypto:hash(sha384, Data) end.
get_hmacfun(?ZRTP_HASH_S256) -> fun(Hash, Data) -> crypto:hmac(sha256, Hash, Data) end;
get_hmacfun(?ZRTP_HASH_S384) -> fun(Hash, Data) -> crypto:hmac(sha384, Hash, Data) end.
get_hashlength(?ZRTP_HASH_S256) -> 32;
get_hashlength(?ZRTP_HASH_S384) -> 48.
get_keylength(?ZRTP_CIPHER_AES1) -> 16;
get_keylength(?ZRTP_CIPHER_AES2) -> 24;
get_keylength(?ZRTP_CIPHER_AES3) -> 32.
get_taglength(?ZRTP_AUTH_TAG_HS32) -> 4;
get_taglength(?ZRTP_AUTH_TAG_HS80) -> 10;
get_taglength(?ZRTP_AUTH_TAG_SK32) -> 4;
get_taglength(?ZRTP_AUTH_TAG_SK64) -> 8.

mkhmac(Msg, Hash) ->
	Payload = zrtp:encode_message(Msg),
	Size = size(Payload) - 8,
	<<Data:Size/binary, _/binary>> = Payload,
	<<Mac:8/binary, _/binary>> = crypto:hmac(sha256, Hash, Data),
	Mac.

verify_hmac(_, _, null) ->
	false;
verify_hmac(Msg, Mac, Hash) ->
	Mac == mkhmac(Msg, Hash).
