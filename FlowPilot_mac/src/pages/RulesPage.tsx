import { RulesSettings } from "../components/rules/RulesSettings";

interface RulesPageProps {
  onGroupsChanged?: () => void;
  refreshVersion: number;
}

export function RulesPage({ onGroupsChanged, refreshVersion }: RulesPageProps) {
  return <RulesSettings onGroupsChanged={onGroupsChanged} refreshVersion={refreshVersion} />;
}
