require 'rails_helper'

RSpec.describe CompanyRemediation do
  it_behaves_like 'model with uuid'
  it_behaves_like 'valid factory'
  it_behaves_like 'audited'

  describe 'associations' do
    it { is_expected.to belong_to(:company) }
    it { is_expected.to belong_to(:remediation) }
    it { is_expected.to belong_to(:remediated_by).class_name('User').optional(true) }
    it { is_expected.to belong_to(:assigned_to).class_name('User').optional(true) }
  end

  describe 'validation' do
    subject { build :company_remediation }

    it {
      is_expected.to validate_uniqueness_of(:remediation_id).case_insensitive.scoped_to(:company_id).with_message('already remediated')
    }
  end

  describe 'AASM - state machine' do
    context 'on create' do
      it 'state is detected' do
        expect(subject).to have_state(:detected)
      end
    end

    context 'on remediated' do
      let(:company_remediation) { create :company_remediation }

      it 'sets remediated_at' do
        Timecop.freeze(Time.current.midday) do
          company_remediation.remediate!
          expect(company_remediation.remediated_at).to eq(Time.current)
        end
      end
    end
  end
end
