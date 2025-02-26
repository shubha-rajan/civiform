package services.applicant.question;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.Locale;
import java.util.Optional;
import java.util.OptionalLong;
import junitparams.JUnitParamsRunner;
import models.Applicant;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import repository.ResetPostgres;
import services.LocalizedStrings;
import services.applicant.ApplicantData;
import services.question.types.DateQuestionDefinition;
import support.QuestionAnswerer;

@RunWith(JUnitParamsRunner.class)
public class DateQuestionTest extends ResetPostgres {
  private static final DateQuestionDefinition dateQuestionDefinition =
      new DateQuestionDefinition(
          OptionalLong.of(1),
          "question name",
          Optional.empty(),
          "description",
          LocalizedStrings.of(Locale.US, "question?"),
          LocalizedStrings.of(Locale.US, "help text"));

  private Applicant applicant;
  private ApplicantData applicantData;

  @Before
  public void setUp() {
    applicant = new Applicant();
    applicantData = applicant.getApplicantData();
  }

  @Test
  public void withEmptyApplicantData() {
    ApplicantQuestion applicantQuestion =
        new ApplicantQuestion(dateQuestionDefinition, applicantData, Optional.empty());

    DateQuestion dateQuestion = new DateQuestion(applicantQuestion);

    assertThat(dateQuestion.hasTypeSpecificErrors()).isFalse();
    assertThat(dateQuestion.hasConditionErrors()).isFalse();
  }

  @Test
  public void withApplicantData_passesValidation() {
    ApplicantQuestion applicantQuestion =
        new ApplicantQuestion(dateQuestionDefinition, applicantData, Optional.empty());
    QuestionAnswerer.answerDateQuestion(
        applicantData, applicantQuestion.getContextualizedPath(), "2021-05-10");

    DateQuestion dateQuestion = new DateQuestion(applicantQuestion);

    assertThat(dateQuestion.getDateValue().get()).isEqualTo("2021-05-10");
    assertThat(dateQuestion.hasTypeSpecificErrors()).isFalse();
    assertThat(dateQuestion.hasConditionErrors()).isFalse();
  }
}
