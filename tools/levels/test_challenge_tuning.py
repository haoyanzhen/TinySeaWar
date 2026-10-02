"""Selection regression cases: invalid denominators and holdout must stay honest."""
import unittest

from build_challenge_levels import ROWS, candidate_config
from tune_challenge_difficulty import choose_candidate, eligible, in_target_band, retain_candidate, summarize


def metric(wins, target=.6, invalid=()):
    runs=[{'seed':i, 'end_state':'GuardLimit' if i in invalid else 'Finished',
           'winner_faction':'player' if i<wins else 'enemy', 'duration':100+i} for i in range(20)]
    return summarize(runs,target)


class SelectionTest(unittest.TestCase):
    def test_failure_does_not_count_as_defeat(self):
        result=metric(9,.3,(19,))
        self.assertEqual(result['valid'],19)
        self.assertEqual(result['win_rate'],9/19)
        self.assertEqual(result['invalid_seeds'],[19])

    def test_same_failure_count_different_seed_is_regression(self):
        self.assertFalse(eligible(metric(12,invalid=(18,)),metric(7,invalid=(19,))))

    def test_band_stop_preserves_original_invalid_seed_without_adding_one(self):
        control=metric(7,invalid=(19,))
        self.assertTrue(in_target_band(metric(11,invalid=(19,)),control,.05))
        self.assertFalse(in_target_band(metric(11,invalid=(18,)),control,.05))

    def test_happy_rate_cannot_override_technical_failure(self):
        control=metric(7)
        self.assertEqual(choose_candidate(control,{1:metric(12,invalid=(19,)),2:metric(10)}),2)

    def test_tie_and_no_improvement(self):
        self.assertEqual(choose_candidate(metric(7),{1:metric(11),2:metric(13)}),1)
        self.assertEqual(choose_candidate(metric(7),{1:metric(7),2:metric(6)}),0)

    def test_holdout_rejects_overfit_without_reselection(self):
        self.assertFalse(retain_candidate(metric(7),metric(12),metric(11),metric(15)))
        self.assertTrue(retain_candidate(metric(7),metric(12),metric(9),metric(11)))
        self.assertFalse(retain_candidate(metric(7),metric(12),metric(9),metric(11,invalid=(19,))))
        self.assertFalse(retain_candidate(metric(7),metric(12),metric(0,invalid=range(20)),metric(11)))
        self.assertEqual(choose_candidate(metric(0,invalid=range(20)),{1:metric(12)}),0)

    def test_paired_report_retains_pairs_missing_both_members(self):
        from summarize_challenge_tuning import paired
        def runs(invalid):
            return [{'seed':i,'end_state':'GuardLimit' if i in invalid else 'Finished',
                     'winner_faction':'enemy','duration':100.0} for i in range(20)]
        result=paired(runs({19}),runs({18,19}))
        self.assertEqual(result['complete_pairs'],18)
        self.assertEqual(result['missing_pairs'],[18,19])

    def test_replacements_leave_rosters_and_optional_targets_resolvable(self):
        from build_challenge_levels import MASTERY
        for code,_,_,_,axis,player,enemy,_ in ROWS:
            for stage in ([0] if code=='l02' else range(4)):
                _, replacements, waves=candidate_config(code,stage,axis,player,enemy)
                roster=[replacements.get(s,s) for s in enemy.split()]
                self.assertEqual(len(roster),len(set(roster)),(code,stage))
                for group in MASTERY.get(code,[]):
                    for ship in group:self.assertIn(replacements.get(ship,ship),roster)
                self.assertEqual(roster[0],enemy.split()[0])
                if code=='m04' and stage:self.assertEqual(waves,[(60,'hood' if stage==3 else 'ward','RN')])
                if code=='l05' and stage:self.assertEqual([w[0] for w in waves],[120,240])


if __name__=='__main__':unittest.main()
