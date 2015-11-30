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

-module(zrtp_fsm).
-author('lemenkov@gmail.com').

-behaviour(gen_server).

-export([start_link/1]).
-export([init/1]).
-export([handle_call/3]).
-export([handle_cast/2]).
-export([handle_info/2]).
-export([code_change/3]).
-export([terminate/2]).

-compile(export_all).

-include("../include/zrtp.hrl").

-record(state, {
		parent = null,
		zid,
		ssrc,
		h0,
		h1,
		h2,
		h3,
		iv,
		hash = null,
		cipher = null,
		auth = null,
		keyagr = null,
		sas = null,

		rs1IDi = null,
		rs1IDr = null,
		rs2IDi = null,
		rs2IDr = null,
		auxSecretIDi = null,
		auxSecretIDr = null,
		pbxSecretIDi = null,
		pbxSecretIDr = null,
		dhPriv = null,
		dhPubl = null,
		shared = <<>>,
		s0 = null,

		srtp_key_i = null,
		srtp_salt_i = null,
		srtp_key_r = null,
		srtp_salt_r = null,
		hmac_key_i = null,
		hmac_key_r = null,
		confirm_key_i = null,
		confirm_key_r = null,
		sas_val = null,

		other_zid = null,
		other_ssrc = null,
		other_h0 = null,
		other_h1 = null,
		other_h2 = null,
		other_h3 = null,
		prev_sn = 0,

		storage = null,
		tref = null
	}
).

start_link(Args) ->
	gen_server:start_link(?MODULE, Args, []).

%% Generate Alice's ZRTP server
init([Parent])->
	init([Parent, null, null]);
init([Parent, ZID, SSRC]) ->
	init([Parent, ZID, SSRC, ?ZRTP_HASH_ALL_SUPPORTED, ?ZRTP_CIPHER_ALL_SUPPORTED, ?ZRTP_AUTH_ALL_SUPPORTED, ?ZRTP_KEY_AGREEMENT_ALL_SUPPORTED, ?ZRTP_SAS_TYPE_ALL_SUPPORTED]);
init([Parent, ZID, SSRC, Hashes, Ciphers, Auths, KeyAgreements, SASTypes] = Params) ->
	% Deferred init
	self() ! {init, Params},
	{ok, #state{}}.

handle_call(
	init,
	_From,
	#state{
		zid = ZID,
		ssrc = MySSRC,
		h3 = H3,
		h2 = H2,
		storage = Tid
	} = State) ->

	% Stop init timer if any
	(State#state.tref == null) orelse timer:cancel(State#state.tref),

	HelloMsg = #hello{
		h3 = H3,
		zid = ZID,
		s = 0, % FIXME allow checking digital signature (see http://zfone.com/docs/ietf/rfc6189bis.html#SignSAS )
		m = 1, % FIXME allow to set to false
		p = 0, % We can send COMMIT messages
		hash = ets:lookup_element(Tid, hash, 2),
		cipher = ets:lookup_element(Tid, cipher, 2),
		auth = ets:lookup_element(Tid, auth, 2),
		keyagr = ets:lookup_element(Tid, keyagr, 2),
		sas = ets:lookup_element(Tid, sas, 2)
	},

	Hello = #zrtp{
		sequence = 1,
		ssrc = MySSRC,
		message = HelloMsg#hello{mac = zrtp_crypto:mkhmac(HelloMsg, H2)}
	},

	% Store full Alice's HELLO message
	ets:insert(Tid, {{alice, hello}, Hello}),

	{reply, Hello, State#state{tref = null}};

handle_call(
	#zrtp{
		sequence = SN,
		ssrc = SSRC,
		message = #hello{
			h3 = HashImageH3,
			zid = ZID,
			s = S,
			m = M,
			p = P,
			hash = Hashes,
			cipher = Ciphers,
			auth = Auths,
			keyagr = KeyAgreements,
			sas = SASTypes
		}
	} = Hello,
	_From,
	#state{
		ssrc = MySSRC,
		storage = Tid
	} = State) ->
	Hash = negotiate(Tid, hash, ?ZRTP_HASH_S256, Hashes),
	Cipher = negotiate(Tid, cipher, ?ZRTP_CIPHER_AES1, Ciphers),
	Auth = negotiate(Tid, auth, ?ZRTP_AUTH_TAG_HS32, Auths),
	KeyAgr = negotiate(Tid, keyagr, ?ZRTP_KEY_AGREEMENT_DH3K, KeyAgreements),
	SAS = negotiate(Tid, sas, ?ZRTP_SAS_TYPE_B32, SASTypes),

	% Store full Bob's HELLO message
	ets:insert(Tid, {{bob, hello}, Hello}),

	{reply,
		#zrtp{sequence = SN+1, ssrc = MySSRC, message = helloack},
		State#state{
			hash = Hash,
			cipher = Cipher,
			auth = Auth,
			keyagr = KeyAgr,
			sas = SAS,
			other_zid = ZID,
			other_ssrc = SSRC,
			other_h3 = HashImageH3,
			prev_sn = SN}
	};

handle_call(
	#zrtp{
		sequence = SN,
		ssrc = SSRC,
		message = helloack
	} = HelloAck,
	_From,
	#state{
		zid = ZID,
		ssrc = MySSRC,
		h3 = H3,
		h2 = H2,
		h1 = H1,
		h0 = H0,
		hash = Hash,
		cipher = Cipher,
		auth = Auth,
		keyagr = KeyAgr,
		sas = SAS,
		other_ssrc = SSRC,
		storage = Tid
	} = State) ->

	#zrtp{message = HelloMsg} = ets:lookup_element(Tid, {bob, hello}, 2),

	HashFun = zrtp_crypto:get_hashfun(Hash),
	HMacFun = zrtp_crypto:get_hmacfun(Hash),

	% FIXME check for preshared keys instead of regenerating them - should we use Mnesia?
	Rs1 = ets:lookup_element(Tid, rs1, 2),
	Rs2 = ets:lookup_element(Tid, rs2, 2),
	Rs3 = ets:lookup_element(Tid, rs3, 2),
	Rs4 = ets:lookup_element(Tid, rs4, 2),

	<<Rs1IDi:8/binary, _/binary>> = HMacFun(Rs1, "Initiator"),
	<<Rs1IDr:8/binary, _/binary>> = HMacFun(Rs1, "Responder"),
	<<Rs2IDi:8/binary, _/binary>> = HMacFun(Rs2, "Initiator"),
	<<Rs2IDr:8/binary, _/binary>> = HMacFun(Rs2, "Responder"),
	<<AuxSecretIDi:8/binary, _/binary>> = HMacFun(Rs3, H3),
	<<AuxSecretIDr:8/binary, _/binary>> = HMacFun(Rs3, H3),
	<<PbxSecretIDi:8/binary, _/binary>> = HMacFun(Rs4, "Initiator"),
	<<PbxSecretIDr:8/binary, _/binary>> = HMacFun(Rs4, "Responder"),

	{PublicKey, PrivateKey} = ets:lookup_element(Tid, {pki,KeyAgr}, 2),

	% We must generate DHPart2 here
	DHpart2Msg = mkdhpart2(H0, H1, Rs1IDi, Rs2IDi, AuxSecretIDi, PbxSecretIDi, PublicKey),
	ets:insert(Tid, {dhpart2msg, DHpart2Msg}),

	Hvi = calculate_hvi(HelloMsg, DHpart2Msg, HashFun),

	CommitMsg = #commit{
		h2 = H2,
		zid = ZID,
		hash = Hash,
		cipher = Cipher,
		auth = Auth,
		keyagr = KeyAgr,
		sas = SAS,
		hvi = Hvi
	},

	Commit = #zrtp{
		sequence = SN + 1,
		ssrc = MySSRC,
		message = CommitMsg#commit{mac = zrtp_crypto:mkhmac(CommitMsg, H1)}
	},

	% Store full Alice's COMMIT message
	ets:insert(Tid, {{alice, commit}, Commit}),

	{reply, Commit,
		State#state{
			rs1IDi = Rs1IDi,
			rs1IDr = Rs1IDr,
			rs2IDi = Rs2IDi,
			rs2IDr = Rs2IDr,
			auxSecretIDi = AuxSecretIDi,
			auxSecretIDr = AuxSecretIDr,
			pbxSecretIDi = PbxSecretIDi,
			pbxSecretIDr = PbxSecretIDr,
			dhPriv = PrivateKey,
			dhPubl = PublicKey
		}
	};

handle_call(
	#zrtp{
		sequence = SN,
		ssrc = SSRC,
		message = #commit{
			h2 = HashImageH2,
			zid = ZID,
			hash = Hash,
			cipher = Cipher,
			auth = Auth,
			keyagr = KeyAgr,
			sas = SAS,
			hvi = Hvi
		}
	} = Commit,
	_From,
	#state{
		ssrc = MySSRC,
		other_ssrc = SSRC,
		other_zid = ZID,
		h1 = H1,
		h0 = H0,
		hash = Hash,
		cipher = Cipher,
		auth = Auth,
		keyagr = KeyAgr,
		sas = SAS,
		rs1IDr = Rs1IDr,
		rs2IDr = Rs2IDr,
		auxSecretIDr = AuxSecretIDr,
		pbxSecretIDr = PbxSecretIDr,
		dhPubl = PublicKey,
		prev_sn = SN0,
		storage = Tid
	} = State) when SN > SN0 ->

	% Lookup Bob's HELLO packet
	Hello = ets:lookup_element(Tid, {bob, hello}, 2),

	case verify_hmac(Hello, HashImageH2) of
		true ->

			% Store full Bob's COMMIT message
			ets:insert(Tid, {{bob, commit}, Commit}),

			% Lookup Alice's COMMIT packet
			#zrtp{message = #commit{hvi = MyHvi}} = ets:lookup_element(Tid, {alice, commit}, 2),

			% Check for lowest Hvi
			case Hvi < MyHvi of
				true ->
					% We're Initiator so do nothing and wait for the DHpart1
					{reply, ok, State#state{other_h2 = HashImageH2, prev_sn = SN}};
				false ->
					DHpart1Msg = mkdhpart1(H0, H1, Rs1IDr, Rs2IDr, AuxSecretIDr, PbxSecretIDr, PublicKey),
					DHpart1 = #zrtp{sequence = SN+1, ssrc = MySSRC, message = DHpart1Msg},

					% Store full Alice's DHpart1 message
					ets:insert(Tid, {{alice, dhpart1}, DHpart1}),

					{reply, DHpart1, State#state{other_h2 = HashImageH2, prev_sn = SN}}
			end;
		false ->
			{reply, #error{code = ?ZRTP_ERROR_HELLO_MISMATCH}, State}
	end;

handle_call(
	#zrtp{
		sequence = SN,
		ssrc = SSRC,
		message = #dhpart1{
			h1 = HashImageH1,
			rs1IDr = Rs1IDr,
			rs2IDr = Rs2IDr,
			auxsecretIDr = AuxsecretIDr,
			pbxsecretIDr = PbxsecretIDr,
			pvr = Pvr
		}
	} = DHpart1,
	_From,
	#state{
		zid = ZIDi,
		ssrc = MySSRC,
		other_ssrc = SSRC,
		other_zid = ZIDr,
		h1 = H1,
		h0 = H0,
		hash = Hash,
		cipher = Cipher,
		sas = SAS,
		rs1IDi = Rs1IDi,
		rs2IDi = Rs2IDi,
		auxSecretIDi = AuxSecretIDi,
		pbxSecretIDi = PbxSecretIDi,
		dhPriv = PrivateKey,
		prev_sn = SN0,
		storage = Tid
	} = State) when SN > SN0 ->

	% Lookup Bob's COMMIT packet
	Commit = ets:lookup_element(Tid, {bob, commit}, 2),

	case verify_hmac(Commit, HashImageH1) of
		true ->
			% Store full Bob's DHpart1 message
			ets:insert(Tid, {{bob, dhpart1}, DHpart1}),

			% Calculate ZRTP params
			DHpart2Msg = ets:lookup_element(Tid, dhpart2msg, 2),

			DHpart2 = #zrtp{sequence = SN+1, ssrc = MySSRC, message = DHpart2Msg},

			% Store full Alice's DHpart2 message
			ets:insert(Tid, {{alice, dhpart2}, DHpart2}),

			% Calculate DHresult
			DHresult = zrtp_crypto:mkfinal(Pvr, PrivateKey),

			% Calculate total hash - http://zfone.com/docs/ietf/rfc6189bis.html#DHSecretCalc
			HashFun = zrtp_crypto:get_hashfun(Hash),
			#zrtp{message = HelloMsg} = ets:lookup_element(Tid, {bob, hello}, 2),
			#zrtp{message = CommitMsg} = ets:lookup_element(Tid, {alice, commit}, 2),

			% http://zfone.com/docs/ietf/rfc6189bis.html#SharedSecretDetermination
			TotalHash = HashFun(<< <<(zrtp:encode_message(X))/binary>> || X <- [HelloMsg, CommitMsg, DHpart1#zrtp.message, DHpart2Msg] >>),
			KDF_Context = <<ZIDi/binary, ZIDr/binary, TotalHash/binary>>,
			% We have to set s1, s2, s3 to null for now - FIXME
			S0 = HashFun(<<1:32, DHresult/binary, "ZRTP-HMAC-KDF", ZIDi/binary, ZIDr/binary, TotalHash/binary, 0:32, 0:32, 0:32 >>),

			% Derive keys
			HLength = zrtp_crypto:get_hashlength(Hash),
			KLength = zrtp_crypto:get_keylength(Cipher),

			% SRTP keys
			<<MasterKeyI:KLength/binary, _/binary>> = zrtp_crypto:kdf(Hash, S0, <<"Initiator SRTP master key">>, KDF_Context),
			<<MasterSaltI:14/binary, _/binary>> = zrtp_crypto:kdf(Hash, S0, <<"Initiator SRTP master salt">>, KDF_Context),
			<<MasterKeyR:KLength/binary, _/binary>> = zrtp_crypto:kdf(Hash, S0, <<"Responder SRTP master key">>, KDF_Context),
			<<MasterSaltR:14/binary, _/binary>> = zrtp_crypto:kdf(Hash, S0, <<"Responder SRTP master salt">>, KDF_Context),

			<<HMacKeyI:HLength/binary, _/binary>> = zrtp_crypto:kdf(Hash, S0, <<"Initiator HMAC key">>, KDF_Context),
			<<HMacKeyR:HLength/binary, _/binary>> = zrtp_crypto:kdf(Hash, S0, <<"Responder HMAC key">>, KDF_Context),

			<<ConfirmKeyI:KLength/binary, _/binary>> = zrtp_crypto:kdf(Hash, S0, <<"Initiator ZRTP key">>, KDF_Context),
			<<ConfirmKeyR:KLength/binary, _/binary>> = zrtp_crypto:kdf(Hash, S0, <<"Responder ZRTP key">>, KDF_Context),

			<<ZRTPSessKey:HLength/binary, _/binary>> = zrtp_crypto:kdf(Hash, S0, <<"ZRTP Session Key">>, KDF_Context),
			<<ExportedKey:HLength/binary, _/binary>> = zrtp_crypto:kdf(Hash, S0, <<"Exported key">>, KDF_Context),

			% http://zfone.com/docs/ietf/rfc6189bis.html#SASType
			<<SASValue:4/binary, _/binary>> = zrtp_crypto:kdf(Hash, S0, <<"SAS">>, KDF_Context),
			SASString = zrtp_crypto:sas(SASValue, SAS),

			{reply, DHpart2,
				State#state{
					other_h1 = HashImageH1,
					prev_sn = SN,
					s0 = S0,
					srtp_key_i = MasterKeyI,
					srtp_salt_i = MasterSaltI,
					srtp_key_r = MasterKeyR,
					srtp_salt_r = MasterSaltR,
					hmac_key_i = HMacKeyI,
					hmac_key_r = HMacKeyR,
					confirm_key_i = ConfirmKeyI,
					confirm_key_r = ConfirmKeyR,
					sas_val = SASString
				}
			};
		false ->
			{reply, #error{code = ?ZRTP_ERROR_HELLO_MISMATCH}, State}
	end;

handle_call(
	#zrtp{
		sequence = SN,
		ssrc = SSRC,
		message = #dhpart2{
			h1 = HashImageH1,
			rs1IDi = Rs1IDo,
			rs2IDi = Rs2IDi,
			auxsecretIDi = AuxsecretIDi,
			pbxsecretIDi = PbxsecretIDi,
			pvi = Pvi
		}
	} = DHpart2,
	_From,
	#state{
		zid = ZIDr,
		ssrc = MySSRC,
		dhPriv = PrivateKey,
		other_ssrc = SSRC,
		hash = Hash,
		cipher = Cipher,
		sas = SAS,
		h0 = H0,
		iv = IV,
		other_zid = ZIDi,
		prev_sn = SN0,
		storage = Tid
	} = State) when SN > SN0 ->

	% Lookup Bob's COMMIT packet
	Commit = ets:lookup_element(Tid, {bob, commit}, 2),

	case verify_hmac(Commit, HashImageH1) of
		true ->
			% Store full Bob's DHpart2 message
			ets:insert(Tid, {{bob, dhpart2}, DHpart2}),

			% Calculate DHresult
			DHresult = zrtp_crypto:mkfinal(Pvi, PrivateKey),

			% Calculate total hash - http://zfone.com/docs/ietf/rfc6189bis.html#DHSecretCalc
			HashFun = zrtp_crypto:get_hashfun(Hash),
			#zrtp{message = HelloMsg} = ets:lookup_element(Tid, {alice, hello}, 2),
			#zrtp{message = CommitMsg} = ets:lookup_element(Tid, {bob, commit}, 2),
			#zrtp{message = DHpart1Msg} = ets:lookup_element(Tid, {alice, dhpart1}, 2),

			% http://zfone.com/docs/ietf/rfc6189bis.html#SharedSecretDetermination
			TotalHash = HashFun(<< <<(zrtp:encode_message(X))/binary>> || X <- [HelloMsg, CommitMsg, DHpart1Msg, DHpart2#zrtp.message] >>),
			KDF_Context = <<ZIDi/binary, ZIDr/binary, TotalHash/binary>>,
			% We have to set s1, s2, s3 to null for now - FIXME
			S0 = HashFun(<<1:32, DHresult/binary, "ZRTP-HMAC-KDF", ZIDi/binary, ZIDr/binary, TotalHash/binary, 0:32, 0:32, 0:32 >>),

			% Derive keys
			HLength = zrtp_crypto:get_hashlength(Hash),
			KLength = zrtp_crypto:get_keylength(Cipher),

			% SRTP keys
			<<MasterKeyI:KLength/binary, _/binary>> = zrtp_crypto:kdf(Hash, S0, <<"Initiator SRTP master key">>, KDF_Context),
			<<MasterSaltI:14/binary, _/binary>> = zrtp_crypto:kdf(Hash, S0, <<"Initiator SRTP master salt">>, KDF_Context),
			<<MasterKeyR:KLength/binary, _/binary>> = zrtp_crypto:kdf(Hash, S0, <<"Responder SRTP master key">>, KDF_Context),
			<<MasterSaltR:14/binary, _/binary>> = zrtp_crypto:kdf(Hash, S0, <<"Responder SRTP master salt">>, KDF_Context),

			<<HMacKeyI:HLength/binary, _/binary>> = zrtp_crypto:kdf(Hash, S0, <<"Initiator HMAC key">>, KDF_Context),
			<<HMacKeyR:HLength/binary, _/binary>> = zrtp_crypto:kdf(Hash, S0, <<"Responder HMAC key">>, KDF_Context),

			<<ConfirmKeyI:KLength/binary, _/binary>> = zrtp_crypto:kdf(Hash, S0, <<"Initiator ZRTP key">>, KDF_Context),
			<<ConfirmKeyR:KLength/binary, _/binary>> = zrtp_crypto:kdf(Hash, S0, <<"Responder ZRTP key">>, KDF_Context),

			<<ZRTPSessKey:HLength/binary, _/binary>> = zrtp_crypto:kdf(Hash, S0, <<"ZRTP Session Key">>, KDF_Context),
			<<ExportedKey:HLength/binary, _/binary>> = zrtp_crypto:kdf(Hash, S0, <<"Exported key">>, KDF_Context),

			% http://zfone.com/docs/ietf/rfc6189bis.html#SASType
			<<SASValue:4/binary, _/binary>> = zrtp_crypto:kdf(Hash, S0, <<"SAS">>, KDF_Context),
			SASString = zrtp_crypto:sas(SASValue, SAS),

			% FIXME add actual values as well as SAS
			HMacFun = zrtp_crypto:get_hmacfun(Hash),
			EData = crypto:aes_ctr_encrypt(ConfirmKeyR, IV, <<H0/binary, 0:15, 0:9, 0:4, 0:1, 0:1, 1:1, 0:1, 16#FFFFFFFF:32>>),
			ConfMac = HMacFun(HMacKeyR, EData),

			Confirm1Msg = #confirm1{
				conf_mac = ConfMac,
				cfb_init_vect = IV,
				encrypted_data = EData
			},

			{reply, #zrtp{sequence = SN+1, ssrc = MySSRC, message = Confirm1Msg},
				State#state{
					other_h1 = HashImageH1,
					prev_sn = SN,
					s0 = S0,
					srtp_key_i = MasterKeyI,
					srtp_salt_i = MasterSaltI,
					srtp_key_r = MasterKeyR,
					srtp_salt_r = MasterSaltR,
					hmac_key_i = HMacKeyI,
					hmac_key_r = HMacKeyR,
					confirm_key_i = ConfirmKeyI,
					confirm_key_r = ConfirmKeyR,
					sas_val = SASString
				}
			};
		false ->
			{reply, #error{code = ?ZRTP_ERROR_HELLO_MISMATCH}, State}
	end;

handle_call(
	#zrtp{
		sequence = SN,
		ssrc = SSRC,
		message = #confirm1{
			conf_mac = ConfMac,
			cfb_init_vect = IV,
			encrypted_data = EData
		}
	} = Confirm1,
	_From,
	#state{
		h0 = H0,
		hash = Hash,
		srtp_key_i = MasterKeyI,
		srtp_salt_i = MasterSaltI,
		srtp_key_r = MasterKeyR,
		srtp_salt_r = MasterSaltR,
		hmac_key_i = HMacKeyI,
		hmac_key_r = HMacKeyR,
		confirm_key_i = ConfirmKeyI,
		confirm_key_r = ConfirmKeyR,
		ssrc = MySSRC,
		other_ssrc = SSRC,
		other_h3 = HashImageH3,
		other_h2 = HashImageH2,
		other_h1 = HashImageH1,
		prev_sn = SN0,
		storage = Tid
	} = State) when SN > SN0 ->

	% Verify HMAC chain
	HMacFun = zrtp_crypto:get_hmacfun(Hash),
	ConfMac = HMacFun(HMacKeyR, EData),
	<<HashImageH0:32/binary, _Mbz:15, SigLen:9, 0:4, E:1, V:1, A:1, D:1, CacheExpInterval:4/binary, Rest/binary>> = crypto:aes_ctr_decrypt(ConfirmKeyR, IV, EData),

%	Signature = case SigLen of
%		0 -> null;
%		_ ->
%			SigLenBytes = (SigLen - 1) * 4,
%			<<SigType:4/binary, SigData:SigLenBytes/binary>> = Rest,
%			#signature{type = SigType, data = SigData}
%	end,

	% Verify HMAC chain
	HashImageH1 = crypto:hash(sha256, HashImageH0),
	HashImageH2 = crypto:hash(sha256, HashImageH1),
	HashImageH3 = crypto:hash(sha256, HashImageH2),

	% Lookup Bob's DHpart1 packet
	DHpart1 = ets:lookup_element(Tid, {bob, dhpart1}, 2),

	case verify_hmac(DHpart1, HashImageH0) of
		true ->
			% Store full Bob's CONFIRM1 message
			ets:insert(Tid, {{bob, confirm1}, Confirm1}),

			% FIXME add actual values as well as SAS
			HMacFun = zrtp_crypto:get_hmacfun(Hash),
			EData2 = crypto:aes_ctr_encrypt(ConfirmKeyI, IV, <<H0/binary, 0:15, 0:9, 0:4, 0:1, 0:1, 1:1, 0:1, 16#FFFFFFFF:32>>),
			ConfMac2 = HMacFun(HMacKeyI, EData2),

			Confirm2Msg = #confirm2{
				conf_mac = ConfMac2,
				cfb_init_vect = IV,
				encrypted_data = EData2
			},

			{reply, #zrtp{sequence = SN+1, ssrc = MySSRC, message = Confirm2Msg}, State#state{other_h0 = HashImageH0, prev_sn = SN}};
		false ->
			{reply, #error{code = ?ZRTP_ERROR_HELLO_MISMATCH}, State}
	end;

handle_call(
	#zrtp{
		sequence = SN,
		ssrc = SSRC,
		message = #confirm2{
			conf_mac = ConfMac,
			cfb_init_vect = IV,
			encrypted_data = EData
		}
	} = Confirm2,
	_From,
	#state{
		parent = Parent,
		h0 = H0,
		hash = Hash,
		cipher = Cipher,
		auth = Auth,
		srtp_key_i = KeyI,
		srtp_salt_i = SaltI,
		srtp_key_r = KeyR,
		srtp_salt_r = SaltR,
		hmac_key_i = HMacKeyI,
		hmac_key_r = HMacKeyR,
		confirm_key_i = ConfirmKeyI,
		confirm_key_r = ConfirmKeyR,
		ssrc = MySSRC,
		other_ssrc = SSRC,
		prev_sn = SN0,
		storage = Tid
	} = State) when SN > SN0 ->

	% Verify HMAC chain
	HMacFun = zrtp_crypto:get_hmacfun(Hash),
	ConfMac = HMacFun(HMacKeyI, EData),
	<<HashImageH0:32/binary, _Mbz:15, SigLen:9, 0:4, E:1, V:1, A:1, D:1, CacheExpInterval:4/binary, Rest/binary>> = crypto:aes_ctr_decrypt(ConfirmKeyI, IV, EData),

%	Signature = case SigLen of
%		0 -> null;
%		_ ->
%			SigLenBytes = (SigLen - 1) * 4,
%			<<SigType:4/binary, SigData:SigLenBytes/binary>> = Rest,
%			#signature{type = SigType, data = SigData}
%	end,

	% Verify HMAC chain
	HashImageH1 = crypto:hash(sha256, HashImageH0),
	HashImageH2 = crypto:hash(sha256, HashImageH1),
	HashImageH3 = crypto:hash(sha256, HashImageH2),

	% Lookup Bob's DHpart2 packet
	DHpart2 = ets:lookup_element(Tid, {bob, dhpart2}, 2),

	case verify_hmac(DHpart2, HashImageH0) of
		true ->
			% We must send blocking request here
			% And we're Responder
			(Parent == null) orelse gen_server:call(Parent, {prepcrypto,
					{SSRC, Cipher, Auth, zrtp_crypto:get_taglength(Auth), KeyI, SaltI},
					{MySSRC, Cipher, Auth, zrtp_crypto:get_taglength(Auth), KeyR, SaltR}}
			),
			{reply, #zrtp{sequence = SN+1, ssrc = MySSRC, message = conf2ack}, State};
		false ->
			{reply, #error{code = ?ZRTP_ERROR_HELLO_MISMATCH}, State}
	end;

handle_call(
	#zrtp{
		sequence = SN,
		ssrc = SSRC,
		message = conf2ack
	} = Conf2Ack,
	_From,
	#state{
		cipher = Cipher,
		auth = Auth,
		ssrc = MySSRC,
		other_ssrc = SSRC,
		parent = Parent,
		srtp_key_i = KeyI,
		srtp_salt_i = SaltI,
		srtp_key_r = KeyR,
		srtp_salt_r = SaltR
	} = State) ->

	% We must send blocking request here
	% And we're Initiator
	(Parent == null) orelse gen_server:call(Parent, {gocrypto,
			{MySSRC, Cipher, Auth, zrtp_crypto:get_taglength(Auth), KeyI, SaltI},
			{SSRC, Cipher, Auth, zrtp_crypto:get_taglength(Auth), KeyR, SaltR}}
	),

	{reply, ok, State};

handle_call({ssrc, MySSRC}, _From, #state{ssrc = null, tref = null} = State) ->
	{A1,A2,A3} = os:timestamp(),
	random:seed(A1, A2, A3),
	Interval = random:uniform(2000),
	{ok, TRef} = timer:send_interval(Interval, init),
	{reply, ok, State#state{ssrc = MySSRC, tref = TRef}};

handle_call(get_keys, _From, State) ->
	{reply,
		{
			State#state.srtp_key_i,
			State#state.srtp_salt_i,
			State#state.srtp_key_r,
			State#state.srtp_salt_i
		},
		State};

handle_call(Other, _From, State) ->
	{reply, error, State}.

handle_cast(Other, State) ->
	{noreply, State}.

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

terminate(Reason, State) ->
	ok.

handle_info({init, [Parent, ZID, MySSRC, Hashes, Ciphers, Auths, KeyAgreements, SASTypes]}, State) ->
	Z = case ZID of
		null -> crypto:rand_bytes(96);
		_ -> ZID
	end,

	% First hash is a random set of bytes
	% Th rest are a chain of hashes made with predefined hash function
	H0 = crypto:rand_bytes(32),
	H1 = crypto:hash(sha256, H0),
	H2 = crypto:hash(sha256, H1),
	H3 = crypto:hash(sha256, H2),

	IV = crypto:rand_bytes(16),

	Tid = ets:new(zrtp, [private]),

	% Filter out requested lists and die if we'll find any unsupported value
	validate_and_save(Tid, hash, ?ZRTP_HASH_ALL_SUPPORTED, Hashes),
	validate_and_save(Tid, cipher, ?ZRTP_CIPHER_ALL_SUPPORTED, Ciphers),
	validate_and_save(Tid, auth, ?ZRTP_AUTH_ALL_SUPPORTED, Auths),
	validate_and_save(Tid, keyagr, ?ZRTP_KEY_AGREEMENT_ALL_SUPPORTED, KeyAgreements),
	validate_and_save(Tid, sas, ?ZRTP_SAS_TYPE_ALL_SUPPORTED, SASTypes),

	% To speedup things later we precompute all keys - we have a plenty of time for that right now
	lists:map(fun(KA) -> {PublicKey, PrivateKey} = zrtp_crypto:mkdh(KA), ets:insert(Tid, {{pki,KA}, {PublicKey, PrivateKey}}) end, KeyAgreements),

	% Likewise - prepare Rs1,Rs2,Rs3,Rs4 values now for further speedups
	lists:map(fun(Atom) -> ets:insert(Tid, {Atom, crypto:rand_bytes(32)}) end, [rs1, rs2, rs3, rs4]),

	{noreply, #state{
			parent = Parent,
			zid = Z,
			ssrc = MySSRC,
			h0 = H0,
			h1 = H1,
			h2 = H2,
			h3 = H3,
			iv = IV,
			storage = Tid
		}
	};
handle_info(init, #state{parent = Parent, zid = ZID, ssrc = MySSRC, h3 = H3, h2 = H2, storage = Tid} = State) ->
	% Stop init timer
	timer:cancel(State#state.tref),

	HelloMsg = #hello{
		h3 = H3,
		zid = ZID,
		s = 0, % FIXME allow checking digital signature (see http://zfone.com/docs/ietf/rfc6189bis.html#SignSAS )
		m = 1, % FIXME allow to set to false
		p = 0, % We can send COMMIT messages
		hash = ets:lookup_element(Tid, hash, 2),
		cipher = ets:lookup_element(Tid, cipher, 2),
		auth = ets:lookup_element(Tid, auth, 2),
		keyagr = ets:lookup_element(Tid, keyagr, 2),
		sas = ets:lookup_element(Tid, sas, 2)
	},

	Hello = #zrtp{
		sequence = 1,
		ssrc = MySSRC,
		message = HelloMsg#hello{mac = zrtp_crypto:mkhmac(HelloMsg, H2)}
	},

	% Store full Alice's HELLO message
	ets:insert(Tid, {{alice, hello}, Hello}),

	(Parent == null) orelse gen_server:cast(Parent, {Hello, null, null}),

	{noreply, State#state{tref = null}};

handle_info(Other, State) ->
	{noreply, State}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%
%%% Various helpers
%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

calculate_hvi(#hello{} = Hello, #dhpart2{} = DHPart2, HashFun) ->
	HelloBin = zrtp:encode_message(Hello),
	DHPart2Bin = zrtp:encode_message(DHPart2),
	HashFun(<<DHPart2Bin/binary, HelloBin/binary>>).

verify_hmac(#zrtp{message = #hello{zid = ZID, mac = Mac} = Msg} = Packet, H2) ->
	zrtp_crypto:verify_hmac(Msg, Mac, H2);
verify_hmac(#zrtp{message = #commit{mac = Mac} = Msg} = Packet, H1) ->
	zrtp_crypto:verify_hmac(Msg, Mac, H1);
verify_hmac(#zrtp{message = #dhpart1{mac = Mac} = Msg} = Packet, H0) ->
	zrtp_crypto:verify_hmac(Msg, Mac, H0);
verify_hmac(#zrtp{message = #dhpart2{mac = Mac} = Msg} = Packet, H0) ->
	zrtp_crypto:verify_hmac(Msg, Mac, H0);
verify_hmac(_, _) ->
	false.

mkdhpart1(H0, H1, Rs1IDr, Rs2IDr, AuxSecretIDr, PbxSecretIDr, PublicKey) ->
	<<_:32, Pvr/binary>> = PublicKey,
	DHpart1 = #dhpart1{
		h1 = H1,
		rs1IDr = Rs1IDr,
		rs2IDr = Rs2IDr,
		auxsecretIDr = AuxSecretIDr,
		pbxsecretIDr = PbxSecretIDr,
		pvr = Pvr
	},
	Mac = zrtp_crypto:mkhmac(DHpart1, H0),
	DHpart1#dhpart1{mac = Mac}.
mkdhpart2(H0, H1, Rs1IDi, Rs2IDi, AuxSecretIDi, PbxSecretIDi, PublicKey) ->
	<<_:32, Pvi/binary>> = PublicKey,
	DHpart2 = #dhpart2{
		h1 = H1,
		rs1IDi = Rs1IDi,
		rs2IDi = Rs2IDi,
		auxsecretIDi = AuxSecretIDi,
		pbxsecretIDi = PbxSecretIDi,
		pvi = Pvi
	},
	Mac = zrtp_crypto:mkhmac(DHpart2, H0),
	DHpart2#dhpart2{mac = Mac}.

validate_and_save(Tid, RecId, Default, List) ->
	% Each value from List must be a member of a Default list
	lists:foreach(fun(X) -> true = lists:member(X, Default) end, List),
	% Now let's sort the List list according the the Default list
	SortedList = lists:filter(fun(X) -> lists:member(X, List) end, Default),
	ets:insert(Tid, {RecId, SortedList}).

negotiate(Tid, RecId, Default, BobList) ->
	AliceList = ets:lookup_element(Tid, RecId, 2),
	negotiate(Default, AliceList, BobList).

negotiate(Default, [], _) ->
	Default;
negotiate(Default, _, []) ->
	Default;
negotiate(_, AliceList, BobList) ->
	[Item | _] = lists:filter(fun(X) -> lists:member(X, AliceList) end, BobList),
	Item.
