// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IVoter, IBoostVoter, IBribe, IVotingEscrow} from "./interfaces/IMezoVe.sol";

/// @title BribeRadarLens
/// @notice On-chain radar telemetry lens scanning Mezo Voter (veBTC) and BoostVoter (veMEZO)
///         gauges to rank MUSD-equivalent bribe return per vote.
contract BribeRadarLens {
    struct GaugeBlip {
        address gauge;
        address bribeContract;
        uint256 currentWeight;
        uint256 totalBribeRatePerSecond;
        uint256 estimatedEpochUSDPerVote;
    }

    IVoter public immutable poolsVoter;
    IBoostVoter public immutable boostVoter;
    IVotingEscrow public immutable veBTC;
    IVotingEscrow public immutable veMEZO;

    constructor(address _poolsVoter, address _boostVoter, address _veBTC, address _veMEZO) {
        require(_poolsVoter != address(0), "Zero address");
        require(_boostVoter != address(0), "Zero address");
        require(_veBTC != address(0), "Zero address");
        require(_veMEZO != address(0), "Zero address");
        poolsVoter = IVoter(_poolsVoter);
        boostVoter = IBoostVoter(_boostVoter);
        veBTC = IVotingEscrow(_veBTC);
        veMEZO = IVotingEscrow(_veMEZO);
    }

    function scanBoostGauges(uint256 offset, uint256 limit) external view returns (GaugeBlip[] memory blips) {
        uint256 total = boostVoter.length();
        if (offset >= total) return new GaugeBlip[](0);
        uint256 count = offset + limit > total ? total - offset : limit;
        blips = new GaugeBlip[](count);

        for (uint256 i = 0; i < count; i++) {
            address g = boostVoter.gauges(offset + i);
            address b = boostVoter.gaugeToBribe(g);
            uint256 w = boostVoter.weights(g);
            uint256 rateSum = 0;
            if (b != address(0)) {
                try IBribe(b).rewardsListLength() returns (uint256 rLen) {
                    for (uint256 j = 0; j < rLen; j++) {
                        address rTok = IBribe(b).rewards(j);
                        rateSum += IBribe(b).rewardRate(rTok);
                    }
                } catch {}
            }
            uint256 epochYield = rateSum * 7 days;
            uint256 perVote = w > 0 ? (epochYield * 1e18) / w : epochYield;
            blips[i] = GaugeBlip({
                gauge: g,
                bribeContract: b,
                currentWeight: w,
                totalBribeRatePerSecond: rateSum,
                estimatedEpochUSDPerVote: perVote
            });
        }
    }
}
