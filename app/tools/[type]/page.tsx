import CalculatorClient from "./CalculatorClient";

type CalculatorPageProps = {
  params: Promise<{ type: string }>;
};

export default async function CalculatorPage({ params }: CalculatorPageProps) {
  const { type } = await params;
  return <CalculatorClient type={type} />;
}
