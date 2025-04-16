# Using a Capacity Block for ML reservations with AWS Batch

AWS Batch is able to make efficient use of your [Capacity Blocks for ML](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-capacity-blocks.html) by providing you a queue to send your jobs to before the capacity block reservation (CBR) becomes active. Batch will scale your CBR instances once they become available and place your jobs onto them. Once the jobs are finished, the instances will scale down automatically. If the capacity block time limit is reached prior to jobs finishing, instances will still be scaled down and the jobs will be marked with a status of FAILED, allowing you to view which may not have completed within the reservation time limits. 

For more information refer to the associated blog post for this repo at:

[BLOG POST TITLE](BLOG POST URL)

## Instructions

For deploying the example resources in your own AWS account, follow the instructions outlined in [HOW-TO.md](HOW-TO.md)

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the LICENSE file.