import { RulesSettings } from "../components/rules/RulesSettings";

interface RulesPageProps {
  refreshVersion: number;
}

export function RulesPage({ refreshVersion }: RulesPageProps) {
  return <RulesSettings refreshVersion={refreshVersion} />;
}
